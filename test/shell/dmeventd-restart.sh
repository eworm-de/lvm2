#!/usr/bin/env bash

# Copyright (C) 2008 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing to use,
# modify, copy, or redistribute it subject to the terms and conditions
# of the GNU General Public License v.2.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA


SKIP_WITH_LVMPOLLD=1

. lib/inittest

aux prepare_dmeventd

aux prepare_vg 5

lvcreate -aey --type mirror -m 3 --nosync --ignoremonitoring -l1 -n 4way $vg
lvchange --monitor y $vg/4way
lvcreate -aey --type mirror -m 2 --nosync --ignoremonitoring -l1 -n 3way $vg
lvchange --monitor y $vg/3way

lvcreate -aey -l1 -n $lv1 $vg
lvcreate -s -l1 -n $lv2 $vg/$lv1

dmeventd -R -f &
echo $! >LOCAL_DMEVENTD
sleep 2 # wait a bit, so we talk to the new dmeventd later

check lv_field $vg/3way seg_monitor "monitored"
check lv_field $vg/4way seg_monitor "monitored"
lvchange --monitor y --verbose $vg/3way 2>&1 | tee lvchange.out
# only non-cluster tests can check command result
test -e LOCAL_CLVMD || grep 'already monitored' lvchange.out
lvchange --monitor y --verbose $vg/4way 2>&1 | tee lvchange.out
test -e LOCAL_CLVMD || grep 'already monitored' lvchange.out

# now try what happens if no dmeventd is running
kill -9 "$(< LOCAL_DMEVENTD)"
rm LOCAL_DMEVENTD debug.log*

dmeventd -R -f &
echo $! >LOCAL_DMEVENTD

# wait longer as tries 5s to communicate with killed daemon
sleep 7
# now dmeventd should not be running
not pgrep dmeventd
rm LOCAL_DMEVENTD

# First lvs restarts 'dmeventd' (initiate a socket connection to a daemon)
check lv_field $vg/3way seg_monitor "not monitored"
pgrep -o dmeventd >LOCAL_DMEVENTD
check lv_field $vg/4way seg_monitor "not monitored"

lvchange --monitor y --verbose $vg/3way 2>&1 | tee lvchange.out
test -e LOCAL_CLVMD || not grep 'already monitored' lvchange.out

lvchange --monitor y --verbose $vg/$lv2 2>&1 | tee lvchange.out
test -e LOCAL_CLVMD || not grep 'already monitored' lvchange.out

rm -f debug.log*
dmeventd -R -f -e "$PWD/test_nologin" -ldddd > debug.log_DMEVENTD_$RANDOM 2>&1 &
echo $! >LOCAL_DMEVENTD

for i in $(seq 1 10); do
  test "$(pgrep -o dmeventd)" = "$(< LOCAL_DMEVENTD)" && break
  sleep .1
done

kill -INT "$(< LOCAL_DMEVENTD)"
sleep 1

# dmeventd should be still present (although in 'exit-mode')
pgrep -o dmeventd

# Create a file simulating 'shutdown in progress'
touch test_nologin
sleep 2

# Should be now dead (within ~1 second)
not pgrep -o dmeventd
rm -f LOCAL_DMEVENTD

# Do not run dmeventd here again
vgremove -ff --config 'activation/monitoring = 0' $vg
