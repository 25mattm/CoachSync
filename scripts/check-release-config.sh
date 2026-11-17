#!/bin/sh
# Refuses to archive a build that still carries the public placeholders from
# Config/Shared.xcconfig. Runs as a build phase on the app targets; ordinary builds, tests
# and CI (ACTION=build) pass straight through. Real values go in Config/Local.xcconfig.
[ "$ACTION" = "install" ] || exit 0

status=0
case "$PRODUCT_BUNDLE_IDENTIFIER" in
  com.example.*)
    echo "error: Bundle identifier is still the com.example placeholder. Set COACHSYNC_BUNDLE_ID_PREFIX in Config/Local.xcconfig."
    status=1 ;;
esac
if [ -z "$DEVELOPMENT_TEAM" ]; then
  echo "error: No development team. Set COACHSYNC_DEVELOPMENT_TEAM in Config/Local.xcconfig."
  status=1
fi
# Plain http is accepted only on the configured private-network domain, the one host the app's
# transport security exception allows.
private_domain="$COACHSYNC_PRIVATE_NETWORK_DOMAIN"
[ "$private_domain" = "localhost" ] && private_domain=""
case "$COACHSYNC_BACKEND_URL" in
  https://*) ;;
  http://*."$private_domain"|http://*."$private_domain":*|http://*."$private_domain"/*)
    if [ -z "$private_domain" ]; then
      echo "error: COACHSYNC_BACKEND_URL must be https unless COACHSYNC_PRIVATE_NETWORK_DOMAIN is set."
      status=1
    fi ;;
  *)
    echo "error: COACHSYNC_BACKEND_URL must be an https URL for a release, or on COACHSYNC_PRIVATE_NETWORK_DOMAIN (now: '$COACHSYNC_BACKEND_URL'). Set it in Config/Local.xcconfig."
    status=1 ;;
esac
case "$COACHSYNC_PRIVACY_POLICY_URL" in
  https://*) ;;
  *)
    echo "error: COACHSYNC_PRIVACY_POLICY_URL must be an https URL for a release (now: '$COACHSYNC_PRIVACY_POLICY_URL'). Set it in Config/Local.xcconfig."
    status=1 ;;
esac
exit $status
