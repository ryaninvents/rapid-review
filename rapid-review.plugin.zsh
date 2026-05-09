# rapid-review — antigen entry point.
#
# Antigen sources this file after cloning the repo. We add the bundled
# `scripts/` directory to $PATH so commands like `review-start`, `review-shell`,
# `nvim-review`, etc. are available everywhere.

local _rr_dir="${0:A:h}"
case ":$PATH:" in
  *":$_rr_dir/scripts:"*) ;;        # already present — skip
  *) export PATH="$_rr_dir/scripts:$PATH" ;;
esac
