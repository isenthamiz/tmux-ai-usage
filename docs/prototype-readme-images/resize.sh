#!/bin/bash
# PROTOTYPE: step the demo client's width while VHS records.
sleep "${1:-3}"
for x in 90 76 60 46 60 76 90 110; do tmux -L outer resize-pane -t o:0.0 -x $x; sleep 2.2; done
