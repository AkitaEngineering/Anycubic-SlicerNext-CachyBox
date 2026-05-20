#!/usr/bin/fish

set script_dir (cd (dirname (status filename)); and pwd)
exec bash "$script_dir/install-core.sh" $argv