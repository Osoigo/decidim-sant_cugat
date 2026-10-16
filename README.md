# decidim_sant_cugat

Citizen Participation and Open Government application.

This is the open-source repository for decidim_sant_cugat, based on [Decidim](https://github.com/AjuntamentdeBarcelona/decidim).

## Setting up the application

You will need to do some steps before having the app working properly once you've deployed it:

1. Open a Rails console in the server: `bundle exec rails console`
2. Create a System Admin user:
```ruby
user = Decidim::System::Admin.new(email: <email>, password: <password>, password_confirmation: <password>)
user.save!
```
3. Visit `<your app url>/system` and login with your system admin credentials
4. Create a new organization. Check the locales you want to use for that organization, and select a default locale.
5. Set the correct default host for the organization, otherwise the app will not work properly. Note that you need to include any subdomain you might be using.
6. Fill the rest of the form and submit it.

You're good to go!

## Customizations

### 2022-09-28 Participatory process Barris 2022

For this specific process, customer wanted users to be redirected to the specific process of each
neighborhood based on the census data. This has been accomplished by:

- implementing a service `ParticipatoryProcessPicker2022`
- customizing the login_modal and the head_extra partials

When this process finishes, this code could be removed or disabled in some way.

### 2026-10-05 Signup form hardening

Measure 3 of the anti-bot plan, after the September 2026 account analysis.

- `config/initializers/invisible_captcha.rb` turns on the timestamp check that Decidim ships
  disabled, with a five second threshold, and limits it to form submissions: Decidim registers
  the filter for every action of the signup and questionnaire controllers, and on a GET there is
  no timestamp in session yet, so the page itself would be treated as spam.
- The signup page must not be served from a shared cache or a caching proxy: the timestamp lives
  in the session.
- The disposable email domain list travels inside the `valid_email2` gem. Run
  `bundle update valid_email2 --conservative` periodically, ideally as part of the release
  routine: between 7.0.13 and 7.1.0 the list grew by around 10.000 domains.
