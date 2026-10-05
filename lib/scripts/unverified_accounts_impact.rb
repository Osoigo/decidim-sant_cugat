# frozen_string_literal: true

# Impacto de eliminar o bloquear las cuentas sin verificación censal.
#
# SOLO LECTURA. Cuenta cuántas cuentas quedarían y cuántas de las afectadas
# tienen contenido, por tipo. Considera verificadas las que tienen autorización
# censal vigente o la tuvieron (historial de versiones y transferencias), y
# excluye administradores, roles de organización, cuentas oficializadas y roles
# en procesos y asambleas.
#
# Uso:
#   RAILS_ENV=production bundle exec rails runner lib/scripts/unverified_accounts_impact.rb
#
# También se puede pegar tal cual en la consola de Rails.

require "set"
A = "Decidim::UserBaseEntity"
users = Decidim::User.where(deleted_at: nil)
all_ids = users.pluck(:id).to_set
vigente = Decidim::Authorization.where(name: "census_authorization_handler").where.not(granted_at: nil).pluck(:decidim_user_id).to_set
pasada = ActiveRecord::Base.connection.select_values(<<~SQL).compact.map(&:to_i).to_set
  SELECT (object->>'decidim_user_id')::bigint FROM versions
   WHERE item_type = 'Decidim::Authorization' AND object->>'name' = 'census_authorization_handler'
  UNION
  SELECT (object_changes->'decidim_user_id'->>1)::bigint FROM versions
   WHERE item_type = 'Decidim::Authorization' AND object_changes->'name'->>1 = 'census_authorization_handler'
SQL
pasada.merge(Decidim::AuthorizationTransfer.pluck(:user_id, :source_user_id).flatten.compact) if defined?(Decidim::AuthorizationTransfer)
gestion = Set.new
gestion.merge(users.where(admin: true).pluck(:id))
gestion.merge(users.where("cardinality(roles) > 0").pluck(:id))
gestion.merge(users.where.not(officialized_at: nil).pluck(:id))
gestion.merge(Decidim::ParticipatoryProcessUserRole.pluck(:decidim_user_id)) if defined?(Decidim::ParticipatoryProcessUserRole)
gestion.merge(Decidim::AssemblyUserRole.pluck(:decidim_user_id)) if defined?(Decidim::AssemblyUserRole)
gestion &= all_ids
quedan_estricto = (vigente | gestion) & all_ids
quedan = (vigente | pasada | gestion) & all_ids
afectadas = all_ids - quedan
bloqueadas = users.where(blocked: true).pluck(:id).to_set
gestionadas = users.where(managed: true).pluck(:id).to_set
grupos = {
  "Activas" => afectadas - bloqueadas - gestionadas,
  "Gestionadas (votaron sin registrarse)" => (afectadas & gestionadas) - bloqueadas,
  "Ya bloqueadas" => afectadas & bloqueadas
}
def ids(label)
  yield.compact.map(&:to_i).to_set
rescue StandardError => e
  puts "  AVISO: #{label} no disponible (#{e.class})"
  Set.new
end
tipos = {
  "Propuestas" => ids("propuestas") { Decidim::Coauthorship.where(decidim_author_type: A, coauthorable_type: "Decidim::Proposals::Proposal").reorder(nil).distinct.pluck(:decidim_author_id) },
  "Borradores colaborativos" => ids("borradores") { Decidim::Coauthorship.where(decidim_author_type: A, coauthorable_type: "Decidim::Proposals::CollaborativeDraft").reorder(nil).distinct.pluck(:decidim_author_id) },
  "Apoyos a propuestas" => ids("apoyos") { Decidim::Proposals::ProposalVote.reorder(nil).distinct.pluck(:decidim_author_id) },
  "Votos de presupuestos" => ids("presupuestos") { Decidim::Budgets::Order.where.not(checked_out_at: nil).reorder(nil).distinct.pluck(:decidim_user_id) },
  "Comentarios" => ids("comentarios") { Decidim::Comments::Comment.where(decidim_author_type: A).reorder(nil).distinct.pluck(:decidim_author_id) },
  "Votos a comentarios" => ids("votos a comentarios") { Decidim::Comments::CommentVote.where(decidim_author_type: A).reorder(nil).distinct.pluck(:decidim_author_id) },
  "Adhesiones" => ids("adhesiones") { Decidim::Endorsement.where(decidim_author_type: A).reorder(nil).distinct.pluck(:decidim_author_id) },
  "Inscripciones a reuniones" => ids("inscripciones") { Decidim::Meetings::Registration.reorder(nil).distinct.pluck(:decidim_user_id) },
  "Reuniones creadas" => ids("reuniones") { Decidim::Meetings::Meeting.where(decidim_author_type: A).reorder(nil).distinct.pluck(:decidim_author_id) },
  "Encuestas" => ids("encuestas") { Decidim::Forms::Answer.reorder(nil).distinct.pluck(:decidim_user_id) },
  "Encuestas de reuniones" => ids("encuestas de reuniones") { Decidim::Meetings::Answer.reorder(nil).distinct.pluck(:decidim_user_id) },
  "Debates" => ids("debates") { Decidim::Debates::Debate.where(decidim_author_type: A).reorder(nil).distinct.pluck(:decidim_author_id) },
  "Enmiendas" => ids("enmiendas") { Decidim::Amendment.reorder(nil).distinct.pluck(:decidim_user_id) },
  "Entradas de blog" => ids("blog") { Decidim::Blogs::Post.where(decidim_author_type: A).reorder(nil).distinct.pluck(:decidim_author_id) },
  "Mensajes privados" => ids("mensajes") { Decidim::Messaging::Message.reorder(nil).distinct.pluck(:decidim_sender_id) },
  "Seguimientos" => ids("seguimientos") { Decidim::Follow.reorder(nil).distinct.pluck(:decidim_user_id) }
}
cualquiera = tipos.values.reduce(Set.new, :|)
sin_seguir = tipos.reject { |k, _| k == "Seguimientos" }.values.reduce(Set.new, :|)
puts "Cuentas no borradas: #{all_ids.size}"
puts "Quedarían con verificación vigente o gestión: #{quedan_estricto.size}"
puts "Quedarían con verificación vigente, pasada o gestión: #{quedan.size}  (gestión: #{gestion.size})"
puts "Afectadas: #{afectadas.size}"
grupos.each do |nombre, g|
  puts
  puts "== #{nombre}: #{g.size} | con algún contenido: #{(g & cualquiera).size} | sin contar seguimientos: #{(g & sin_seguir).size}"
  tipos.each { |t, s| n = (g & s).size; puts format("   %-28s %8d", t, n) if n.positive? }
end
nil
