import logging
from tbot.runtime import _shadow_observability as o

o.patch_logging_emit()
log = logging.getLogger("p0_heartbeat_test")
log.setLevel(logging.INFO)

msg = "INFO  | 2026-02-19T00:00:00 | SELFTEST | HEARTBEAT\nin_session=True pre_close=False\nportfolio_kill=False\n"
log.info(msg)
print("WROTE_LOG_LINE")
