# Minimal legal-page placement

Status: draft pages are bundled in all three clients. User supplied `sakaygaray` as the domain/name to use for now; no suffix or email address has been assumed. Pages use SakayGaray and explicitly state that they are drafts, not yet effective policies.

- Passenger authentication: two links accessible before email registration and Google sign-in.
- Passenger account menu: the same links for later reference.
- Driver authentication and driver profile: the same links, including the driver-document and location disclosures.
- Admin authentication: privacy access for staff account processing; avoid copying passenger acceptance steps into administration workflows.
- Do not put repeated notices on live maps, pickup buttons, ETA labels or ride-completion screens.
- Do not add mandatory acceptance or claim acceptance is stored without explicitly implementing the intended acceptance workflow.

Existing support copy contains `support@parago.com`, but its ownership and availability have not been verified. The source uses both ParaGO and SAKAY branding. Neither should be silently resolved in legal notices.

The canonical UI and concise draft text are in `tools/legal/legal_pages.dart`. Run `python tools/sync_legal_pages.py` after editing that file to synchronize the three independent Flutter clients. The Markdown drafts record unresolved owner facts for review; they are not loaded as app content.

Links now appear on passenger, driver and admin authentication screens, in the passenger account menu, and in the driver profile. Locally bundled, scrollable pages work before sign-in without a network request. There is no acceptance checkbox, acceptance storage, database migration or change to login/ride behavior. The passenger widget tests verify opening both policies, returning without losing form input, and scrolling at 320px width with doubled text size.

Before treating these as effective public policies, confirm the legal operator, full public contact address, pilot/public status, retention arrangements and remaining facts identified in the Markdown drafts. The current in-app Support contact route does not provide an unauthenticated public contact address.

Sources consulted for the draft structure:

- National Privacy Commission, right to be informed: https://privacy.gov.ph/the-right-to-be-informed/
- National Privacy Commission, Data Privacy Act: https://privacy.gov.ph/data-privacy-act/

The NPC guidance identifies controller/contact details, processing purposes, retention and rights as information for a privacy notice. Those facts must come from the operator; the repository cannot establish all of them. These drafts are not a declaration of legal compliance.
