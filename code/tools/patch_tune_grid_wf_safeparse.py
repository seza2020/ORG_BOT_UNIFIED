import re
from pathlib import Path

P = Path(r"C:\alpaca-bot\org_bot\tools\tune_grid_wf.ps1")

def main():
    s = P.read_text(encoding="utf-8")

    if "function _SafeDouble" not in s:
        insert = r'''
function _SafeDouble([string]$x, [double]$default = [double]::NaN) {
  if ($null -eq $x) { return $default }
  $t = ($x + "").Trim()
  if ($t -eq "" -or $t -eq "-" -or $t -eq "NA" -or $t -eq "N/A") { return $default }
  try { return [double]$t } catch { return $default }
}
function _SafeInt([string]$x, [int]$default = 0) {
  if ($null -eq $x) { return $default }
  $t = ($x + "").Trim()
  if ($t -eq "" -or $t -eq "-" -or $t -eq "NA" -or $t -eq "N/A") { return $default }
  try { return [int]$t } catch { return $default }
}
'''
        # put helpers near top (after param block or at file start)
        m = re.search(r'(?is)^\s*param\s*\(', s)
        if m:
            # find end of param(...)
            depth = 0
            i = m.start()
            j = m.end()-1
            for k in range(j, len(s)):
                if s[k] == '(':
                    depth += 1
                elif s[k] == ')':
                    depth -= 1
                    if depth <= 0:
                        j = k+1
                        break
            s = s[:j] + "\n" + insert + "\n" + s[j:]
        else:
            s = insert + "\n" + s

    # Replace common direct casts that blow up on "-"
    # 1) [double]$something  -> _SafeDouble $something
    s = re.sub(r'(?i)\[double\]\s*\$(\w+)', r'(_SafeDouble $\\\1)', s)

    # 2) [int]$something -> _SafeInt $something
    s = re.sub(r'(?i)\[int\]\s*\$(\w+)', r'(_SafeInt $\\\1)', s)

    P.write_text(s, encoding="utf-8")
    print("PATCH_OK:", str(P))

if __name__ == "__main__":
    main()
