# frozen_string_literal: true

# Decide qué hacer con cada cuenta en la limpieza de cuentas de spam, según el
# criterio acordado con el Ayuntamiento en octubre de 2026.
#
# No escribe nada: solo clasifica. El script lib/scripts/cleanup_unverified_accounts.rb
# es el que ejecuta las acciones, y en modo simulación se queda únicamente con
# esta clasificación.
#
# El criterio, en el orden en que se aplica:
#
#   :gestion     administración, cuentas oficializadas, con rol en la
#                organización o en un espacio, y participantes privadas
#   :gestionada  cuentas creadas al votar sin registrarse, que por fuerza se
#                identificaron contra el censo
#   :verificada  con autorización vigente, o con rastro de haberla tenido
#   :participo   anteriores al 15 de noviembre de 2020 con participación que
#                exigía identificarse; antes de esa fecha Decidim no guardaba
#                el historial de verificaciones, así que la ausencia de rastro
#                no significa que no se verificaran
#   :bloquear    con contenido y señales claras de spam
#   :borrar      sin ningún contenido
#   :pendiente   con contenido y sin señales de spam: la decisión que el
#                Ayuntamiento se reservó sobre 5.072 cuentas
#   :ya_bloqueada cuentas que administración ya bloqueó
class AccountCleanupPlan
  AUTHOR_TYPE = "Decidim::UserBaseEntity"

  # Primera versión registrada de una autorización en esta plataforma: la
  # trazabilidad de las verificaciones llegó con Decidim 0.22.
  HISTORY_STARTS_AT = Time.zone.parse("2020-11-15 00:00:00")

  SPAM_WORDS = /\b(?:casino|bet|bets|betting|slot|slots|poker|jackpot|bonus|apk|seo|escort|loan|crypto|forex|viagra|cbd|vape|shop|store|agency|marketing|packers|movers|taxi|cab|hotel|tour|travel|clothing|outfit|jewell?ers|nha ?cai|vip|xxx|porn|dating|hack|cheap|discount|review|reviews|digital|studio|consulting|clinic|repair|cleaning|plumber|lawyer|insurance|rental|logistics|trading)\b/i
  URL_RE = %r{https?://|www\.|\b[a-z0-9-]+\.(?:com|net|org|info|biz|io|xyz|top|site|online|shop|store|app|vn|in|ru|cn|co|me|pro|club|live|fun|icu)\b}i

  KEEP = %i[gestion gestionada verificada participo].freeze

  def initialize(scope: nil)
    @scope = scope || Decidim::User.where(deleted_at: nil)
  end

  # Hash de id de cuenta => símbolo de decisión.
  def decisions
    @decisions ||= build_decisions
  end

  def ids_for(decision)
    decisions.select { |_id, value| value == decision }.keys
  end

  def counts
    decisions.values.tally.sort_by { |_decision, count| -count }.to_h
  end

  # De dónde sale la protección de las cuentas verificadas. Importa porque las
  # autorizaciones vigentes caducan y se revocan: casi toda la protección viene
  # del historial reconstruido sobre la tabla versions, no de la tabla de
  # autorizaciones. Si este desglose se desequilibra, el criterio deja de
  # proteger lo que creemos.
  def verification_breakdown
    protegidas = Set.new(ids_for(:verificada))
    fuentes = verification_sources

    {
      total: protegidas.size,
      con_autorizacion_vigente: (protegidas & fuentes[:vigente]).size,
      solo_por_historial: (protegidas - fuentes[:vigente]).size,
      por_transferencia: (protegidas & fuentes[:transferencia]).size
    }
  end

  private

  attr_reader :scope

  def build_decisions
    management = management_ids
    verified = verified_ids
    content = content_ids
    identity_participation = identity_participation_ids
    flagged = moderated_ids

    {}.tap do |result|
      scope.select(columns).find_each(batch_size: 2_000) do |user|
        result[user.id] = decide(user, management:, verified:, content:, identity_participation:, flagged:)
      end
    end
  end

  def columns
    %i[id created_at name nickname email personal_url about admin managed officialized_at roles blocked extended_data]
  end

  def decide(user, management:, verified:, content:, identity_participation:, flagged:)
    return :ya_bloqueada if user.blocked?
    return :gestion if management.include?(user.id) || user.admin? || user.officialized? || user.roles.present?
    return :gestionada if user.managed?
    return :verificada if verified.include?(user.id)
    return :participo if before_history?(user) && identity_participation.include?(user.id)
    return :borrar unless content.include?(user.id)
    return :bloquear if spam_signals?(user, flagged)

    :pendiente
  end

  def before_history?(user)
    user.created_at < HISTORY_STARTS_AT
  end

  def spam_signals?(user, flagged)
    return true if flagged.include?(user.id)
    return true if user.personal_url.present?

    haystack = [display_name(user), user.nickname, user.about].join(" ")
    return true if URL_RE.match?(haystack)
    return true if SPAM_WORDS.match?(haystack)

    disposable_domain?(user.email)
  end

  # Al bloquear, Decidim sustituye el nombre y guarda el original aparte.
  def display_name(user)
    stored = user.extended_data.is_a?(Hash) ? user.extended_data["user_name"] : nil
    stored.presence || user.name.to_s
  end

  def disposable_domain?(email)
    domain = email.to_s.downcase.split("@", 2).last
    return false if domain.blank?

    disposable_domains.include?(domain)
  end

  def disposable_domains
    @disposable_domains ||= begin
      require "valid_email2"
      ValidEmail2.disposable_emails
    rescue LoadError, NameError
      Set.new
    end
  end

  # --- Conjuntos de identificadores, una consulta por fuente ---

  def management_ids
    ids = Set.new
    ids.merge(pluck_safe("roles en procesos") { Decidim::ParticipatoryProcessUserRole.pluck(:decidim_user_id) })
    ids.merge(pluck_safe("roles en asambleas") { Decidim::AssemblyUserRole.pluck(:decidim_user_id) })
    ids.merge(pluck_safe("participantes privadas") { Decidim::ParticipatorySpacePrivateUser.pluck(:decidim_user_id) })
    ids
  end

  def verified_ids
    ids = Set.new
    verification_sources.each_value { |fuente| ids.merge(fuente) }
    ids.delete(nil)
  end

  def verification_sources
    @verification_sources ||= {
      vigente: Set.new(pluck_safe("autorizaciones") { Decidim::Authorization.pluck(:decidim_user_id) }).tap { |s| s.delete(nil) },
      historial: Set.new(pluck_safe("historial de autorizaciones") { authorization_history_ids }).tap { |s| s.delete(nil) },
      transferencia: Set.new(pluck_safe("transferencias") { Decidim::AuthorizationTransfer.pluck(:user_id, :source_user_id).flatten }).tap { |s| s.delete(nil) }
    }
  end

  def authorization_history_ids
    ActiveRecord::Base.connection.select_values(<<~SQL).compact.map(&:to_i)
      SELECT (object->>'decidim_user_id')::bigint FROM versions
       WHERE item_type = 'Decidim::Authorization' AND object IS NOT NULL
      UNION
      SELECT (object_changes->'decidim_user_id'->>1)::bigint FROM versions
       WHERE item_type = 'Decidim::Authorization' AND object_changes IS NOT NULL
    SQL
  end

  # Participación que exige identificarse: apoyos, votos de presupuestos,
  # inscripciones a reuniones, encuestas y enmiendas.
  def identity_participation_ids
    ids = Set.new
    ids.merge(pluck_safe("apoyos") { Decidim::Proposals::ProposalVote.reorder(nil).distinct.pluck(:decidim_author_id) })
    ids.merge(pluck_safe("presupuestos") { Decidim::Budgets::Order.where.not(checked_out_at: nil).reorder(nil).distinct.pluck(:decidim_user_id) })
    ids.merge(pluck_safe("reuniones") { Decidim::Meetings::Registration.reorder(nil).distinct.pluck(:decidim_user_id) })
    ids.merge(pluck_safe("encuestas") { Decidim::Forms::Answer.reorder(nil).distinct.pluck(:decidim_user_id) })
    ids.merge(pluck_safe("enmiendas") { Decidim::Amendment.reorder(nil).distinct.pluck(:decidim_user_id) })
    ids.delete(nil)
  end

  # Cualquier rastro de actividad, incluida la que no exige identificarse.
  def content_ids
    ids = identity_participation_ids.dup
    ids.merge(pluck_safe("registro de acciones") { Decidim::ActionLog.where.not(decidim_user_id: nil).reorder(nil).distinct.pluck(:decidim_user_id) })
    ids.merge(pluck_safe("comentarios") { authored_ids(Decidim::Comments::Comment) })
    ids.merge(pluck_safe("votos a comentarios") { authored_ids(Decidim::Comments::CommentVote) })
    ids.merge(pluck_safe("coautorías") { authored_ids(Decidim::Coauthorship) })
    ids.merge(pluck_safe("adhesiones") { authored_ids(Decidim::Endorsement) })
    ids.merge(pluck_safe("debates") { authored_ids(Decidim::Debates::Debate) })
    ids.merge(pluck_safe("entradas de blog") { authored_ids(Decidim::Blogs::Post) })
    ids.merge(pluck_safe("reuniones creadas") { authored_ids(Decidim::Meetings::Meeting) })
    ids.merge(pluck_safe("mensajes privados") { Decidim::Messaging::Message.reorder(nil).distinct.pluck(:decidim_sender_id) })
    ids.delete(nil)
  end

  # Cuentas con contenido reportado u oculto por moderación, y cuentas
  # reportadas como participantes.
  def moderated_ids
    ids = Set.new
    ids.merge(pluck_safe("moderaciones de participantes") { Decidim::UserModeration.where("report_count > 0").pluck(:decidim_user_id) })
    %w[Decidim::Comments::Comment Decidim::Proposals::Proposal Decidim::Debates::Debate].each do |type|
      ids.merge(pluck_safe("moderaciones de #{type}") { moderated_authors(type) })
    end
    ids.delete(nil)
  end

  def moderated_authors(type)
    reportable_ids = Decidim::Moderation.where(decidim_reportable_type: type)
                                        .where("report_count > 0 OR hidden_at IS NOT NULL")
                                        .pluck(:decidim_reportable_id)
    return [] if reportable_ids.empty?

    case type
    when "Decidim::Proposals::Proposal"
      Decidim::Coauthorship.where(coauthorable_type: type, coauthorable_id: reportable_ids, decidim_author_type: AUTHOR_TYPE)
                           .reorder(nil).distinct.pluck(:decidim_author_id)
    else
      type.constantize.unscoped.where(id: reportable_ids, decidim_author_type: AUTHOR_TYPE)
          .reorder(nil).distinct.pluck(:decidim_author_id)
    end
  end

  def authored_ids(klass)
    klass.where(decidim_author_type: AUTHOR_TYPE).reorder(nil).distinct.pluck(:decidim_author_id)
  end

  def pluck_safe(label)
    Array(yield)
  rescue StandardError => e
    warn("AVISO: no se pudo consultar #{label} (#{e.class}: #{e.message.to_s[0, 120]})")
    []
  end
end
