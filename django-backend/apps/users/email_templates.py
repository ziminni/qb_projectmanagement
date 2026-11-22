"""Branded HTML email templates for Queen Builders CPMS account & security emails.

Table-based layout with inline CSS for consistent rendering across Gmail,
Outlook, Apple Mail, and mobile clients. Every dynamic string is HTML-escaped.
"""

from html import escape

ROLE_LABELS = {
    'admin': 'System Admin',
    'owner': 'Project Manager',
    'site_engineer': 'Foreman',
    'accountant': 'Accountant',
    'client': 'Client',
}


def _format_roles(roles):
    if not roles:
        return ''
    return ', '.join(ROLE_LABELS.get(r, r.replace('_', ' ').title()) for r in roles)


def _layout(*, preheader, badge, heading, body_html, footer_note):
    safe_preheader = escape(preheader)
    safe_badge = escape(badge)
    safe_heading = escape(heading)
    safe_footer = escape(footer_note)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{safe_heading}</title>
</head>
<body style="margin:0;padding:0;background-color:#F4F2ED;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#18181B;-webkit-font-smoothing:antialiased;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">{safe_preheader}</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#F4F2ED;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;width:100%;background-color:#FFFFFF;border-radius:12px;overflow:hidden;border:1px solid #E7E2D8;box-shadow:0 4px 20px rgba(24,24,27,0.06);">
          <!-- Header -->
          <tr>
            <td style="background-color:#1A1816;padding:28px 32px;border-bottom:3px solid #C5A059;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                <tr>
                  <td>
                    <div style="font-size:18px;font-weight:800;letter-spacing:1.4px;color:#FFFFFF;line-height:1.2;">QUEEN BUILDERS</div>
                    <div style="font-size:11px;font-weight:600;letter-spacing:1.2px;color:#C5A059;margin-top:4px;text-transform:uppercase;">Construction Project Management</div>
                  </td>
                  <td align="right" valign="middle">
                    <span style="display:inline-block;padding:5px 10px;border-radius:999px;background-color:rgba(197,160,89,0.16);border:1px solid rgba(197,160,89,0.45);color:#E5C88B;font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;">{safe_badge}</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <!-- Body -->
          <tr>
            <td style="padding:32px 32px 28px 32px;">
              <h1 style="margin:0 0 12px 0;font-size:22px;font-weight:700;color:#18181B;line-height:1.3;">{safe_heading}</h1>
              {body_html}
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="background-color:#FAF9F6;padding:18px 32px;border-top:1px solid #EFECE4;">
              <p style="margin:0;font-size:12px;line-height:1.5;color:#71717A;">{safe_footer}</p>
              <p style="margin:6px 0 0 0;font-size:11px;color:#A1A1AA;">Queen Builders CPMS &middot; Automated security message</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


def render_credentials_email(user, temporary_password, *, is_reset=False):
    """Return ``(subject, plain_text, html)`` for new account or admin reset."""
    name = escape(user.full_name or 'there')
    email = escape(user.email)
    temp_pw = escape(temporary_password)
    roles_text = _format_roles(getattr(user, 'roles', []))
    roles_html = (
        f"""
        <tr>
          <td style="padding:10px 0 0 0;border-top:1px solid #EAE5DC;">
            <div style="font-size:11px;font-weight:700;letter-spacing:0.8px;color:#71717A;text-transform:uppercase;">Assigned Role</div>
            <div style="font-size:14px;font-weight:600;color:#18181B;margin-top:3px;">{escape(roles_text)}</div>
          </td>
        </tr>"""
        if roles_text
        else ''
    )

    if is_reset:
        subject = 'Queen Builders CPMS — Your Temporary Password'
        badge = 'Password Reset'
        heading = 'Your password has been reset'
        intro = 'An administrator has reset your Queen Builders CPMS password. Use the temporary credentials below to sign back in.'
        preheader = 'Your Queen Builders CPMS password was reset. Use your temporary password to sign in.'
    else:
        subject = 'Welcome to Queen Builders CPMS — Your Sign-In Credentials'
        badge = 'New Account'
        heading = 'Welcome to Queen Builders CPMS'
        intro = 'Your account has been created. Use the credentials below to sign in to the Queen Builders CPMS desktop application.'
        preheader = 'Your Queen Builders CPMS account is ready. Sign-in credentials enclosed.'

    body_html = f"""
      <p style="margin:0 0 18px 0;font-size:15px;line-height:1.6;color:#3F3F46;">Hello <strong>{name}</strong>,</p>
      <p style="margin:0 0 22px 0;font-size:14px;line-height:1.6;color:#52525B;">{escape(intro)}</p>

      <!-- Credentials Card -->
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#FAF9F6;border:1px solid #E7E2D8;border-radius:10px;padding:18px 20px;">
        <tr>
          <td style="padding:0 0 12px 0;">
            <div style="font-size:11px;font-weight:700;letter-spacing:0.8px;color:#71717A;text-transform:uppercase;">Email Address</div>
            <div style="font-size:15px;font-weight:600;color:#18181B;margin-top:3px;">{email}</div>
          </td>
        </tr>
        <tr>
          <td style="padding:12px 0 {'12px' if roles_text else '0'} 0;border-top:1px solid #EAE5DC;">
            <div style="font-size:11px;font-weight:700;letter-spacing:0.8px;color:#71717A;text-transform:uppercase;">Temporary Password</div>
            <div style="display:inline-block;margin-top:6px;padding:8px 14px;background-color:#FFFFFF;border:1px solid #DFD7C8;border-radius:6px;font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;font-size:17px;font-weight:700;letter-spacing:1.2px;color:#1A1816;">{temp_pw}</div>
          </td>
        </tr>
        {roles_html}
      </table>

      <!-- Security Notice -->
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin-top:20px;background-color:#FFFBEB;border:1px solid #FDE68A;border-left:4px solid #C5A059;border-radius:8px;">
        <tr>
          <td style="padding:12px 16px;font-size:13px;line-height:1.55;color:#78350F;">
            <strong>First-time sign-in:</strong> For your security, you will be prompted to set and confirm a new permanent password as soon as you log in.
          </td>
        </tr>
      </table>

      <!-- Steps -->
      <div style="margin-top:22px;font-size:13px;line-height:1.7;color:#52525B;">
        <div style="font-weight:700;color:#18181B;margin-bottom:4px;">How to sign in:</div>
        1. Open the <strong>Queen Builders CPMS</strong> desktop app and click <strong>Sign in</strong>.<br>
        2. Enter your email and the temporary password above.<br>
        3. Choose and confirm your new password (at least 8 characters with a letter and a number).
      </div>
    """

    plain_text = (
        f'Hello {user.full_name},\n\n'
        f'{intro}\n\n'
        f'Email: {user.email}\n'
        f'Temporary password: {temporary_password}\n'
        + (f'Role: {roles_text}\n' if roles_text else '')
        + '\nFor your security, you will be prompted to set a new password the '
        'first time you sign in.\n\n'
        '— Queen Builders CPMS'
    )

    html = _layout(
        preheader=preheader,
        badge=badge,
        heading=heading,
        body_html=body_html,
        footer_note='If you were not expecting this account, please contact your System Administrator.',
    )
    return subject, plain_text, html


def render_password_reset_code_email(user, code, *, expires_minutes=15):
    """Return ``(subject, plain_text, html)`` for a 6-digit password reset OTP."""
    name = escape(user.full_name or 'there')
    safe_code = escape(code)
    subject = 'Queen Builders CPMS — Your Password Reset Code'
    heading = 'Reset your password'
    preheader = f'Your Queen Builders CPMS password reset code is {code}. It expires in {expires_minutes} minutes.'

    body_html = f"""
      <p style="margin:0 0 16px 0;font-size:15px;line-height:1.6;color:#3F3F46;">Hello <strong>{name}</strong>,</p>
      <p style="margin:0 0 22px 0;font-size:14px;line-height:1.6;color:#52525B;">
        We received a request to reset your Queen Builders CPMS password. Enter the 6-digit verification code below in the desktop app to choose a new password.
      </p>

      <!-- Verification Code Box -->
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#FAF9F6;border:1px solid #DFD7C8;border-radius:10px;">
        <tr>
          <td align="center" style="padding:24px 20px;">
            <div style="font-size:11px;font-weight:700;letter-spacing:1.2px;color:#71717A;text-transform:uppercase;margin-bottom:10px;">Verification Code</div>
            <div style="font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace;font-size:34px;font-weight:800;letter-spacing:8px;color:#1A1816;padding-left:8px;">{safe_code}</div>
            <div style="font-size:12px;color:#A16207;font-weight:600;margin-top:12px;">Expires in {expires_minutes} minutes</div>
          </td>
        </tr>
      </table>

      <!-- Security Note -->
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin-top:20px;background-color:#F8FAFC;border:1px solid #E2E8F0;border-radius:8px;">
        <tr>
          <td style="padding:12px 16px;font-size:13px;line-height:1.55;color:#475569;">
            Never share this code with anyone. Queen Builders administrators will never ask you for your verification code.
          </td>
        </tr>
      </table>
    """

    plain_text = (
        f'Hello {user.full_name},\n\n'
        'We received a request to reset your Queen Builders CPMS password.\n\n'
        f'Reset code: {code}\n\n'
        f'Enter this code in the app to choose a new password. '
        f'It expires in {expires_minutes} minutes.\n\n'
        'If you did not request a password reset, you can safely ignore this email.\n\n'
        '— Queen Builders CPMS'
    )

    html = _layout(
        preheader=preheader,
        badge='Verification Code',
        heading=heading,
        body_html=body_html,
        footer_note='If you did not request a password reset, you can safely ignore this email — your password will remain unchanged.',
    )
    return subject, plain_text, html
