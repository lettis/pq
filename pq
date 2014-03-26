#!/usr/bin/env python3

#
# pq - version 0.1
#
# Copyright (c) 2014, Florian Sittel (www.lettis.net)
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met: 
# 
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer. 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution. 
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 

desc = """
pq - a simple, personal queueing system.

You can use 'pq' to queue jobs on your machine, i.e. execute
programs depending on your current system load.
Recognized limits are the current load-average value
(as given, e.g. by 'uptime' or 'top') as well as the current
total memory usage (as given, e.g. by 'free').
If the limits -- which can be controlled by
the '--sys-load-limit' and '--sys-mem-limit' options --
for the given values have not been reached, the system's state
is interpreted as idle and the next job in the queue is run.

NOTE:
pq does not include a daemon. Job execution is triggered only by
execution of 'pq -u', resp. 'pq --update'.
To automatically process the queue, run a separate script
to regularly call 'pq -u', e.g. by defining a cron-job (via 'crontab -e').
A typical cron-job definition to update the queue every two minutes would e.g. be
'*/2  * * * * /path/to/pq --update'.

pq is run on a per-user basis and different pq-instances
do not communicate with each other.
The only way pq decides whether to run the next job
or not is by watching the system usage.
The pq configuration is located at $HOME/.config/pq.
This directory contains pq.conf, the configuration file
and other data like the jobs-database.


GENERAL USAGE:
A job is easily added by 

# pq "some_cmd --an-option --other-option args"

Everything in quotes will be interpreted as an ordinary
shell command and be executed as such.
pq automatically saves the directory from which the job has
been submitted and will execute the command in that directory.
Additionally, pq will save current environment variables and
set them before job execution in the executing shell.
The environment variables to be preserved can be set in the pq.conf-file,
per default pq will save $HOME, $LD_LIBRARY_PATH, $PATH and $PYTHONPATH.

Report bugs to sittel@lettis.net.
"""

import os
import subprocess
import socket
import fcntl
import argparse
import configparser
import json

class RunFile:
  def __init__(self, run_file):
    self.run_file = run_file
    self.db = {}

  def enqueue(self, job):
    if not 'last_id' in self.db.keys():
      self.db['last_id'] = 0
      self.db['jobs'] = {}
      self.db['job_queue'] = []
    jobid = self.db['last_id'] + 1
    self.db['jobs'][str(jobid)] = job
    self.db['job_queue'].append(str(jobid))
    self.db['last_id'] = jobid

  def remove(self, jobid):
    jobid = str(jobid)
    try:
      i = self.db['job_queue'].index(jobid)
      del self.db['job_queue'][i]
      del self.db['jobs'][jobid]
    except (KeyError, ValueError):
      pass

  def pop(self):
    try:
      jobid = self.db['job_queue'].pop(0)
    except:
      return None
    job = self.db['jobs'][jobid]
    del self.db['jobs'][jobid]
    return job

  def __iter__(self):
    try:
      for jobid in self.db['job_queue']:
        yield jobid
    except:
      pass

  def __getitem__(self, jobid):
    jobid = str(jobid)
    return self.db['jobs'][jobid]

  def __len__(self):
    try:
      return len(self.db['jobs'])
    except:
      return 0

  def __enter__(self):
    if os.path.isfile(self.run_file):
      self.fh = open(self.run_file, "r+")
      fcntl.lockf(self.fh, fcntl.LOCK_EX)
      try:
        self.db = json.load(self.fh)
      except ValueError:
        self.db = {}
    else:
      self.fh = open(self.run_file, "w")
      self.db = {}
    return self

  def __exit__(self, *ignored):
    self.fh.seek(0)
    json.dump(self.db,
              self.fh,
              separators=(',', ': '),
              indent=2)
    self.fh.truncate()
    fcntl.lockf(self.fh, fcntl.LOCK_UN)
    self.fh.close()



class JobManager:
  def __init__(self, run_file, conf, hostname):
    self.run_file = run_file
    self.conf = conf
    self.hostname = hostname

  def parse_env_variables(self, env_var_def):
    env_var_def = [v.strip() for v in env_var_def.strip().split(",")]
    parsed_vars = {}
    for var in env_var_def:
      try:
        parsed_vars[var] = os.environ[var]
      except KeyError: pass
    return parsed_vars

  def get_mem_usage(self):
    meminfo = open("/proc/meminfo").readlines()
    kb_to_gb = lambda x: x / (1024**2)
    mem_avail = 0
    mem_free = 0
    for line in meminfo:
      if "MemTotal" in line:
        mem_avail = kb_to_gb(int(line.strip().split()[1]))
      elif "MemFree" in line:
        mem_free = kb_to_gb(int(line.strip().split()[1]))
    return round(mem_avail - mem_free, ndigits=2)

  def run(self, job):
    subprocess.Popen(job['cmd'], shell=True, env=job['env'], cwd=job['pwd'])

  def add(self, cmd):
    with RunFile(self.run_file) as jobs:
      env = self.parse_env_variables(conf[self.hostname]['stored_env_variables'])
      jobs.enqueue({
        'cmd': cmd,
        'env': env,
        'host': self.hostname,
        'pwd': os.getcwd() })

  def update(self):
    if (self.get_mem_usage() < float(conf[self.hostname]['mem_limit'])
    and os.getloadavg()[0] < float(conf[self.hostname]['load_limit'])
    and os.getloadavg()[0] <= os.getloadavg()[1]):
      # ok, system is idle (enough), get next
      # job from queue and run it:
      with RunFile(self.run_file) as jobs:
        self.run(jobs.pop())

  def delete(self, jobid):
    with RunFile(self.run_file) as jobs:
      jobs.remove(jobid)

  def print_list(self):
    with RunFile(self.run_file) as jobs:
      for jobid in jobs:
        print(jobid, " ", jobs[jobid]['pwd'], " #  ", jobs[jobid]['cmd'], sep="")

  def print_status(self):
    sys_load = os.getloadavg()[0]
    mem_usage = self.get_mem_usage()
    with RunFile(self.run_file) as jobs:
      print(len(jobs), "jobs in queue")
      print("run job(s) if:")
      print("  system load is below:", conf[self.hostname]['load_limit'])
      print("  memory usage is below:", conf[self.hostname]['mem_limit'], "Gb")
      print("current values:")
      print("  system load:", sys_load)
      print("  memory usage:", mem_usage)


###########################################################################################

parser = argparse.ArgumentParser("pq",
                                 description=desc,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("-u", "--update",
                    dest="update",
                    action="store_true",
                    help="update job status and start new jobs if resources allow it.")

parser.add_argument("-l", "--list",
                    dest="job_list",
                    action="store_true",
                    help="print job list")

parser.add_argument(dest="job_cmd",
                    metavar="JOB_CMD",
                    nargs="?",
                    default=None,
                    help="add job to queue. e.g. # pq 'make -C some_dir'.")

#parser.add_argument("--local",
#                    dest="local_only",
#                    action="store_true",
#                    help="run job only on localhost, i.e. do not distribute to other machines.")

parser.add_argument("-d", "--delete",
                    dest="delete",
                    metavar="JOBID",
                    type=int,
                    help="delete job with given JOBID from queue.")

parser.add_argument("--sys-load-limit",
                    dest="max_load",
                    type=float,
                    help="""set load limit.
                            if system load reaches/tops load limit,
                            no jobs will be started until load goes sufficiently down.
                            (default: 0.5)""")
parser.add_argument("--sys-mem-limit",
                    dest="max_mem",
                    type=float,
                    help="""set memory (RAM) limit (in Gb).
                            if totally used memory reaches/tops mem-limit,
                            no jobs will be started until enough memory is freed.
                            (default: 2)""")
args = parser.parse_args()

# read config
config_dir = os.environ['HOME'] + "/.config/pq"
if not os.path.exists(config_dir):
  os.makedirs(config_dir)
config_file = config_dir + "/pq.conf"
conf = configparser.ConfigParser()
# define basic limits
conf['DEFAULT'] = { 'load_limit': '0.5',
                    'mem_limit': '2',
                    'priority': '10',
                    'stored_env_variables': 'HOME, PATH, LD_LIBRARY_PATH, PYTHONPATH'}
conf.read([config_file])
# look for hostname in config file: if not there, create as section
hostname = socket.gethostbyaddr(socket.gethostname())[0]
if not conf.has_section(hostname):
  conf[hostname] = {}

## handle cmdline arguments
if args.max_load:
  conf[hostname]['load_limit'] = str(args.max_load)
if args.max_mem:
  conf[hostname]['mem_limit'] = str(args.max_mem)

jobs = JobManager(config_dir + "/jobs", conf, hostname)

if args.update:
  jobs.update()
elif args.job_cmd:
  jobs.add(args.job_cmd)
elif args.delete:
  jobs.delete(args.delete)
elif args.job_list:
  jobs.print_list()
else:
  jobs.print_status()

conf.write(open(config_file, "w"))

