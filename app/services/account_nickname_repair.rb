# frozen_string_literal: true

# Decidim valida el apodo contra /\A[a-z0-9_-]+\z/, pero las cuentas de 2018 y
# 2019 traen apodos con tildes, espacios, puntos o emojis, de cuando la
# validación era más laxa. No se citan aquí: son de personas reales.
#
# Eso impide borrarlas. Decidim::DestroyAccount empieza llamando a
# invalidate_all_sessions!, que hace save!, ANTES de vaciar el apodo, así que
# la validación salta y el borrado muere con ActiveRecord::RecordInvalid.
# Decidim::Admin::BlockUser tiene el mismo problema, porque también guarda el
# registro sin tocar el apodo.
#
# La solución es ponerles por delante un apodo válido, saltándose las
# validaciones. El borrado lo va a vaciar igualmente y en el bloqueo el apodo
# no se muestra, así que no se pierde nada que importe.
class AccountNicknameRepair
  VALIDO = /\A[a-z0-9_-]+\z/

  def self.call(user)
    new(user).call
  end

  def initialize(user)
    @user = user
  end

  # Devuelve true si hubo que arreglarlo.
  def call
    return false if user.managed?
    return false if user.nickname.to_s.match?(VALIDO)

    user.update_columns(nickname: apodo_libre)
    true
  end

  private

  attr_reader :user

  def apodo_libre
    candidato = "u#{user.id}"
    return candidato unless tomado?(candidato)

    "u#{user.id}-#{SecureRandom.hex(3)}"
  end

  def tomado?(candidato)
    Decidim::User.where(nickname: candidato).where.not(id: user.id).exists?
  end
end
