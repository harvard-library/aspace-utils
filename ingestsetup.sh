#!/bin/bash

# This script reads the repository codes from repos.file and makes dirs, then 
# copies over files from full ead export to matching repository code dirs.
# Also sets up json output dir, log files

. ./ingest.properties

JSONDIR=$INGESTDIR/ead_json
REPOSFILE=repos.txt

mkdir -p $JSONDIR
mkdir -p $INGESTDIR/logs
mkdir -p $INGESTDIR/logs/archive
while read line; do
	reposcode=`basename $line |cut -c1-3`
	#echo "$reposcode"	
	mkdir -p $INGESTDIR/$reposcode
	if [ -s $INGESTDIR/logs/$reposcode.log ]; then
		currentdate=`date +%Y%m%d%H%M`
		mv $INGESTDIR/logs/$reposcode.log $INGESTDIR/logs/archive/$reposcode.log.$currentdate
	fi
	touch $INGESTDIR/logs/$reposcode.log
	cp $EADDIR/$reposcode*.xml $INGESTDIR/$reposcode
done < $INGESTDIR/$REPOSFILE
