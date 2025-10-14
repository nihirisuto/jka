#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "$(date): Starting autostart script"
# after reboot gotta wait for system to fully initialize 
sleep 15
echo "$(date): Delay complete" 
echo "$(date): Starting server"
TERM=xterm bash -c "cd $SCRIPT_DIR && cd .. && ./autors.sh start > .autors/start_attempt.log"
sleep 5
if screen -ls | grep -q jka; then
    echo "$(date): Screen session successfully created"
else
    echo "$(date): ERROR: Failed to create screen session"
fi
echo "$(date): Autostart script complete"