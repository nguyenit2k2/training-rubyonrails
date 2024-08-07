class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :omniauthable, omniauth_providers: [:google_oauth2]
  has_many :microposts, dependent: :destroy
  has_many :active_relationships,   class_name:   "Relationship",
                                    foreign_key:  "follower_id",
                                    dependent:    :destroy
  has_many :passive_relationships,  class_name:   "Relationship",
                                    foreign_key:  "followed_id",
                                    dependent:    :destroy
  has_many :following, through: :active_relationships, source: :followed
  has_many :followers, through: :passive_relationships, source: :follower
  attr_accessor :remember_token, :activation_token, :reset_token
  before_save   :downcase_email
  before_create :create_activation_digest
  validates :name, presence: true, length: { maximum: 50 }
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  validates :email, presence: true, length: { maximum: 255 },
                    format: { with: VALID_EMAIL_REGEX },
                    uniqueness: true
  validates :password, presence: true, length: { minimum: 6 }, allow_nil: true

  # Returns the hash digest of the given string.
  def User.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST :
                                                  BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  # Returns a random token.
  def User.new_token
    SecureRandom.urlsafe_base64
  end

  # Remembers a user in the database for use in persistent sessions.
  def remember
    self.remember_token = User.new_token
    update_attribute(:remember_digest, User.digest(remember_token))
    remember_digest
  end

  # Returns a session token to prevent session hijacking.
  # We reuse the remember digest for convenience.
  def session_token
    remember_digest || remember
  end

  # Returns true if the given token matches the digest.
  def authenticated?(attribute, token)
    digest = send("#{attribute}_digest")
    return false if digest.nil?
    BCrypt::Password.new(digest).is_password?(token)
  end

  # Forgets a user.
  def forget
    update_attribute(:remember_digest, nil)
  end
   # Activates an account.
   def activate
    update_columns(activated: true, activated_at: Time.zone.now)
  end

  # Sends activation email.
  def send_activation_email
    UserMailer.account_activation(self).deliver_now
  end
  # Sets the password reset attributes.
  def create_reset_digest
    self.reset_token = User.new_token
    update_columns(reset_digest: User.digest(reset_token), reset_sent_at: Time.zone.now)
  end

  # Sends password reset email.
  def send_password_reset_email
    UserMailer.password_reset(self).deliver_now
  end
  def password_reset_expired?
    reset_sent_at < 2.hours.ago
  end
  # Defines a proto-feed.
  # See "Following users" for the full implementation.
  # Returns a user's status feed.
  def feed
    following_ids = "SELECT followed_id FROM relationships
                     WHERE follower_id = :user_id"
    Micropost.where("user_id IN (#{following_ids})
                     OR user_id = :user_id", user_id: id)
             .includes(:user, image_attachment: :blob)
 end

 # Follows a user.
 def follow(other_user)
  following << other_user unless self == other_user
end

# Unfollows a user.
def unfollow(other_user)
  following.delete(other_user)
end

# Returns true if the current user is following the other user.
def following?(other_user)
  following.include?(other_user)
end
def self.from_omniauth(access_token)
  data = access_token.info
  user = User.where(email: data['email']).first

  unless user
    user = User.create(
      name: data['name'],
      email: data['email'],
      password: Devise.friendly_token[0, 20]
    )
  end
  user
end
def google_oauth2
  Rails.logger.info "OmniAuth Data: #{request.env['omniauth.auth'].inspect}"
  @user = User.from_omniauth(request.env['omniauth.auth'])

  if @user.persisted?
    Rails.logger.info "User Authenticated: #{@user.inspect}"
    sign_in_and_redirect @user, event: :authentication
    set_flash_message(:notice, :success, kind: 'Google') if is_navigational_format?
  else
    Rails.logger.info "User Not Authenticated: #{@user.errors.full_messages.join("\n")}"
    session['devise.google_data'] = request.env['omniauth.auth'].except(:extra)
    redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
  end
end


def failure
  redirect_to root_path
end
  private

    # Converts email to all lowercase.
    def downcase_email
      self.email = email.downcase
    end

    # Creates and assigns the activation token and digest.
    def create_activation_digest
      self.activation_token  = User.new_token
      self.activation_digest = User.digest(activation_token)
    end
end