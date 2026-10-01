# Driver credential terminology

The admin driver form now uses **Cooperative / driver reference** as the
operator-facing label. This is a terminology change only in the current
release.

The submitted API field remains `licenseNumber`, and the backend continues to
apply the existing license normalization, duplicate check, and private
front/back document requirements. The helper text in the form makes this
compatibility behavior explicit so the label does not imply that a cooperative
ID has replaced the legal license record.

A true cooperative-ID replacement requires a separate, reviewed migration with
an issuer/cooperative model, new validation rules, record reconciliation, and a
decision about how legally required license evidence is retained.
