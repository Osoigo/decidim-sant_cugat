# frozen_string_literal: true

module DecidimCopyMeetingTaxonomies
  private

  def copy_meeting!
    parsed_title = Decidim::ContentProcessor.parse_with_processor(:hashtag, form.title, current_organization: meeting.organization).rewrite
    parsed_description = Decidim::ContentProcessor.parse_with_processor(:hashtag, form.description, current_organization: meeting.organization).rewrite

    @copied_meeting = Decidim.traceability.create!(
      Decidim::Meetings::Meeting,
      form.current_user,
      taxonomizations: form.taxonomizations,
      title: parsed_title,
      description: parsed_description,
      end_time: form.end_time,
      start_time: form.start_time,
      address: form.address,
      latitude: form.latitude,
      longitude: form.longitude,
      location: form.location,
      location_hints: form.location_hints,
      component: meeting.component,
      private_meeting: form.private_meeting,
      transparent: form.transparent,
      author: form.current_organization,
      questionnaire: form.questionnaire,
      online_meeting_url: form.online_meeting_url,
      type_of_meeting: form.type_of_meeting,
      iframe_embed_type: form.iframe_embed_type,
      iframe_access_level: form.iframe_access_level,
      comments_enabled: form.comments_enabled,
      comments_start_time: form.comments_start_time,
      comments_end_time: form.comments_end_time,
      registration_type: form.registration_type,
      registration_url: form.registration_url,
      **fields_from_meeting
    )
  end
end

Rails.application.config.to_prepare do
  next if Decidim::Meetings::Admin::CopyMeeting < DecidimCopyMeetingTaxonomies

  Decidim::Meetings::Admin::CopyMeeting.prepend(DecidimCopyMeetingTaxonomies)
end