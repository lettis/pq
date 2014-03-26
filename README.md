pq - a simple, personal queueing system.
========================================

You can use 'pq' to queue jobs on your machine, i.e. execute
programs depending on your current system load.
Recognized limits are the current load-average value
(as given, e.g. by 'uptime' or 'top') as well as the current
total memory usage (as given, e.g. by 'free').
If the limits -- which can be controlled by
the '--sys-load-limit' and '--sys-mem-limit' options --
for the given values have not been reached, the system's state
is interpreted as idle and the next job in the queue is run.

NOTE
----
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


GENERAL USAGE
-------------
A job is easily added by 

pq "some_cmd --an-option --other-option args"

Everything in quotes will be interpreted as an ordinary
shell command and be executed as such.
pq automatically saves the directory from which the job has
been submitted and will execute the command in that directory.
Additionally, pq will save current environment variables and
set them before job execution in the executing shell.
The environment variables to be preserved can be set in the pq.conf-file,
per default pq will save $HOME, $LD_LIBRARY_PATH, $PATH and $PYTHONPATH.

Report bugs to sittel@lettis.net.
