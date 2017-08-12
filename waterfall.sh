#!/bin/bash

# Consult https://lwalab.phys.unm.edu/CompScreen/cs.php
HOSTS=lwaucf1,lwaucf2,lwaucf3,lwaucf4,lwaucf5
PROCS=5

INDIR=/data/network/recent_data/jtsai
INFILE=057974_001488585
CODEDIR=$HOME/Radio-Transient-Search

#WORKDIR=/mnt/toaster/cleague/work1b
WORKDIR=$HOME/g296853/work1b

export PYTHONPATH=$CODEDIR:

mkdir -p $WORKDIR
#mpirun -host $HOSTS -npernode 1 mkdir -v -p $WORKDIR

cd $WORKDIR

ln -svf $INDIR/$INFILE .
#mpirun -host $HOSTS -npernode 1 ln -svf $INDIR/$INFILE .

time mpirun -host $HOSTS -np $PROCS -x PYTHONPATH python $CODEDIR/waterfall.py $INFILE |& tee runlog.$$

