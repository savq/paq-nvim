#!/bin/sh

set -e

TESTENV="$PWD/.testenv"
PLUGINS="$TESTENV/data/nvim/site/pack/plugins/start"

# Ensure enviroment is clean
dirs="data/nvim/site/pack/paqs config/nvim state/nvim run/nvim cache/nvim"
for dir in $dirs; do
    rm -rf "$TESTENV/$dir"
    mkdir -p "$TESTENV/$dir"
done
rm "$TESTENV/data/nvim/paq-lock.json"

export XDG_CONFIG_HOME="$TESTENV/config"
export XDG_DATA_HOME="$TESTENV/data"
export XDG_STATE_HOME="$TESTENV/state"
export XDG_RUNTIME_DIR="$TESTENV/run"
export XDG_CACHE_HOME="$TESTENV/cache"

if [ ! -e "$PLUGINS/plenary.nvim" ]; then
    git clone --depth=1 https://github.com/nvim-lua/plenary.nvim.git "$PLUGINS/plenary.nvim"
else
    (cd "$PLUGINS/plenary.nvim" && git pull)
fi

nvim --headless -u test/minimal_init.lua -c "RunTests ${1-test}"

if [ "$?" = 0 ]; then
    echo "Success"
else
    echo "Failed"
fi
