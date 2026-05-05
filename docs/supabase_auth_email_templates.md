# Supabase Auth Email Templates

The branded confirmation email source lives in:

```text
supabase/templates/confirmation.html
```

For a hosted Supabase project, open `Authentication -> Emails -> Confirm signup` in the Supabase Dashboard and paste the HTML into the message body. Set the subject to a neutral value:

```text
Net Infra: email check
```

The template uses Supabase Auth Go template variables:

- `{{ .ConfirmationURL }}` for the verification link.
- `{{ .Email }}` for the recipient email.
- `{{ index .Data "locale" }}`, `{{ index .Data "full_name" }}`, and `{{ index .Data "company_name" }}` from signup metadata.

Localization works because the app sends the current UI language in signup metadata:

```dart
data: {
  'full_name': fullName.trim(),
  'company_name': companyName.trim(),
  'locale': AppI18n.instance.locale.languageCode,
  'locale_name': AppI18n.instance.localeName,
}
```

Supabase does not automatically know the user's app language when it sends an auth email. Pass the locale in metadata, then branch inside the email template with Go template conditions.

Hosted projects that still use the built-in Supabase mailer can reject custom content with `Contains blocked keywords`. The built-in mailer is intentionally limited; keep the subject/body neutral, avoid raw fallback verification URLs, or configure a custom SMTP provider for the fully branded production email.

For local Supabase CLI projects, add this to `supabase/config.toml` after creating the standard Supabase config:

```toml
[auth.email.template.confirmation]
subject = "Net Infra: email check"
content_path = "./supabase/templates/confirmation.html"
```
