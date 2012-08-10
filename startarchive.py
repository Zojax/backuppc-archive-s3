#!/usr/bin/python -W ignore::DeprecationWarning
#
# Quick hack to submit an archive request to the BackupPC daemon from the
# command line. Note that this script probably needs to be run as user
# 'backuppc' (or whatever the BackupPC user is on your system) in order to
# be able to view the pool.

import optparse
import time
import os
from subprocess import Popen, PIPE

BACKUPPCBINDIR = '/usr/share/backuppc/bin'
RF_PREFIX = "archiveInfo." # request file prefix


REQUEST_TEMPLATE = """
    %%ArchiveReq = (
            'archiveloc' => '%(archive_path)s',
            'reqTime' => '%(request_time)s',
            'BackupList' => %(numbers_list)s,
            'host' => '%(archive_host)s',
            'parfile' => '5',
            'archtype' => '0',
            'compression' => '/bin/bzip2',
            'compext' => '.bz2',
            'HostList' => %(hosts)s,
            'user' => '%(user)s',
            'splitsize' => '0000000'
        );
    """

def render_request(archive_path, hosts, numbers_list, archive_host, user):
    """
    Render request template.
    """
    request_time = int(time.time())

    return REQUEST_TEMPLATE % locals()



def list_callback(option, opt, value, parser):
    vals = getattr(parser.values, option.dest, []) or []
    vals.append(str(value))
    setattr(parser.values, option.dest, vals)

def main():
    # check command line options
    parser = optparse.OptionParser(
        usage="Usage: %prog [-A archivehost] [-H archivehost] [-n numlist] [-o outloc] [-u user] hosts_path",
        description="" +
                    "Tool for submitting an archive request to the BackupPC daemon from the command line, " +
                    "needs to be run as user 'backuppc'. "
    )
    parser.add_option("-A", "--archive-host", dest="ahost", default="archive",
        help="Name of archiver host")

    parser.add_option("-H", "--archived-host",
                        dest="hosts", type='string', action='callback',
                        callback=list_callback, default="",
        help="List of archived hosts")

    parser.add_option("-n", "--number",
                        dest="numlist", type='int', action='callback',
                        callback=list_callback, default=0,
        help="List of archive numbers")

    parser.add_option("-o", "--output-path", dest="opath",
        help="Output destination (default=/var/lib/backuppc/removable)", default="/var/lib/backuppc/removable")

    parser.add_option("-u", "--user", dest="user", default="backuppc",
        help="User from who process is started")



    options, args = parser.parse_args()

    print "options, args -> ", options, args

    if len(options.hosts) != len(options.numlist) or not len(options.hosts):
        parser.error('Number of hosts should be equal to the amount of backup numbers')

    if not len(args):
        parser.error('hosts_path argument should be provided')

    hosts_path = os.path.join(args[0], "pc")

    if not os.path.exists(hosts_path):
        parser.error('hosts_path argument should be valid')

    real_hosts = os.listdir(hosts_path)
    for i,n in enumerate(options.numlist):
        if options.hosts[i] not in real_hosts:
            parser.error('Host %s does not exist' % hosts[i])

        backup_path = os.path.join(hosts_path, options.hosts[i], str(n))

        if str(n) != '-1' and (not os.path.exists(backup_path) or not os.path.isdir(backup_path)):
            parser.error("There is no backup %s of host %s" % (n, options.hosts[i]))

    if options.ahost not in real_hosts:
        parser.error('Archive host %s does not exist' % options.ahost)

    if not os.path.exists(options.opath):
        parser.error('Archive destination path does not exist')

    #Create request file
    archive_root = os.path.join(hosts_path, options.ahost)
    req_files = sorted(filter(lambda x: x.startswith(RF_PREFIX), os.listdir(archive_root)))
    next_index = 0
    if len(req_files):
        next_index = int(req_files[-1][len(RF_PREFIX):])+1
    rf_name = RF_PREFIX+str(next_index)
    rf = open(os.path.join(archive_root, rf_name), 'w')
    rf.write(render_request(options.opath, options.hosts, options.numlist, options.ahost, options.user))
    rf.close()
    # Start archiving
    proc = Popen([os.path.join(BACKUPPCBINDIR, "BackupPC_serverMesg"),
                            "archive", options.user, options.ahost, rf_name],
                 stdin=PIPE, stdout=PIPE)
    proc.communicate()


if __name__ == '__main__':
    main()

