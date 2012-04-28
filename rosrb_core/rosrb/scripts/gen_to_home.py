#!/usr/bin/env python
# Generate msg and srv to rosrb directory

import sys
import os
import os.path
import errno
import subprocess
import glob

def mkdir_p(path):
    try:
        os.makedirs(path)
    except OSError as exc: # Python >2.5
        if exc.errno == errno.EEXIST:
            pass
        else: raise

args = sys.argv[1:]
for arg in args:
    home = os.environ['HOME']
    output_path = os.path.join(home, '.ros', 'rosrb_gen')
    mkdir_p(output_path)

    print "output directory is ... %s" % output_path
    targets = subprocess.check_output(["rospack", "depends", arg]).splitlines()
    targets.append(arg)
    for target in targets:
        print "generate msg in %s ..." % target,
        path = subprocess.check_output(["rospack", "find", target]).rstrip()
        msg_dir = os.path.join(path, "msg")
        if os.path.exists(msg_dir) and os.path.isdir(msg_dir):
            msgs = glob.glob(os.path.join(msg_dir, "*.msg"))
            if msgs:
                cmd = ["rosrun", "rosrb", "genmsg_rb.py",
                       "--output-dir", output_path]
                cmd.extend(msgs)
                subprocess.call(cmd)
                cmd = ["rosrun", "rosrb", "genmsg_rb.py",
                       "--generate-root", "--output-dir", output_path]
                cmd.extend(msgs)
                subprocess.call(cmd)
                print "done"
            else:
                print "nothing to generate"
        else:
            print "nothing to generate"

        print "generate srv in %s ..." % target,
        srv_dir = os.path.join(path, "srv")
        if os.path.exists(srv_dir) and os.path.isdir(srv_dir):
            srvs = glob.glob(os.path.join(srv_dir, "*.srv"))
            if srvs:
                cmd = ["rosrun", "rosrb", "gensrv_rb.py",
                       "--output-dir", output_path]
                cmd.extend(srvs)
                subprocess.call(cmd)
                cmd = ["rosrun", "rosrb", "gensrv_rb.py",
                       "--generate-root", "--output-dir", output_path]
                cmd.extend(srvs)
                subprocess.call(cmd)
                print "done"
            else:
                print "nothing to generate"
        else:
            print "nothing to generate"

            



