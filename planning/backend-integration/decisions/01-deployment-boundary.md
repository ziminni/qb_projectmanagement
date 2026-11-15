# Local POS, cloud CPMS

**Status:** Locked boundary; connectivity mechanism unresolved.
**Choice:** Local POS, cloud CPMS. (by: me — user selected this option)

## Boundary

- POS Flutter desktops reach the store's local Django API and PostgreSQL over LAN (or localhost for one workstation).
- CPMS Flutter desktops reach cloud-hosted CPMS Django API over HTTPS; CPMS database remains private.
- Each system retains independent repository, configuration, deployment and data ownership.
- Ordinary POS selling can continue during internet loss while store server, power and LAN remain available. This is not a promise of standalone offline storage on each desktop.
- CPMS remains internet-dependent. Cross-system exchanges wait during disconnection.

## Open design

Choose private VPN/inbound POS API or store-initiated outbound synchronization. Persist operations and reconcile after unknown outcomes; desktop apps must not possess cross-system service secrets. No direct public PostgreSQL access.

Previously imported requests exist locally; new approvals/closures cannot instantly propagate during outages. Cancellation races and stale-data warnings require explicit rules before acceptance.

## Hosting research, not provider selection

- Render free API services sleep after 15 minutes idle; free running hours are shared per workspace (750/month). Free Render PostgreSQL expires after 30 days. Unsuitable as assumed permanent database.
- Neon offers quota-limited free PostgreSQL; verify current quotas and required PostgreSQL major version before selecting.
- Free trials/tiers are demo candidates, not uptime or backup guarantees. Private media storage remains a separate requirement.

Sources: https://render.com/docs/free ; https://neon.com/pricing ; https://neon.com/docs/introduction/plans

No cloud resources created, deployment tested or migrations run.
