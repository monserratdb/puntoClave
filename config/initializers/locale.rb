# Set default locale to Spanish for a consistent Spanish UI/UX
I18n.available_locales = [:en, :es]
Rails.application.config.i18n.available_locales = I18n.available_locales
Rails.application.config.i18n.default_locale = :es
# Ensure fallback to :en if translation missing (requires i18n backend fallbacks)
require 'i18n/backend/fallbacks' unless I18n::Backend.constants.include?(:Fallbacks)
I18n::Backend::Simple.include(I18n::Backend::Fallbacks) unless I18n::Backend::Simple.ancestors.include?(I18n::Backend::Fallbacks)
Rails.application.config.i18n.fallbacks = [:en]
