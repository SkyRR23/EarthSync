# Remaining user actions

- **Rotate/revoke the Earthdata token shared in chat after this test.** Configure
  a replacement in the environment secret manager or a protected local process
  environment as `EARTHDATA_TOKEN`; never paste it into chat or commit it. Restart
  the backend after changing its credential environment. NASA access and the GES
  DISC agreement were genuinely exercised after the user's authorization.
- Complete the [Windows interactive retest](WINDOWS_LOCAL_TESTING.md) against the
  exact draft-PR SHA, using a new checkout/private state. Cloud tests cannot certify
  the user's local ACLs, firewall, browser, fonts or sensor freshness at a later time.
- Review source licensing/quota needs before commercial Open-Meteo use. No billing
  plan, paid product, account upgrade or public deployment was enabled.
- Native Burmese agricultural/accessibility review and independent field accuracy
  validation remain separate from software acceptance. All crop rules stay blocked.
- Review the draft PR and later authorize any reconciliation with the historical
  workstream or merge. No merge or deployment is automatic.

When reporting a Windows finding, retain the tested branch/SHA and redacted
evidence. Reproduce against this real-time candidate, add a meaningful regression,
fix here when relevant and provide exact retest steps. Do not replace private local
state or mark the user's acceptance passed without their confirmation.
