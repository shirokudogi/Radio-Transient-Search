#!/bin/bash
#PBS -l walltime=24:00:00
#PBS -l nodes=2:ppn=6
#PBS -W group_list=hokieone
#PBS -q normal_q
#PBS -A hokieone

# Add any the intel compiler and MPT MPI modules
#module reset
#module load mkl mpiblast python
#module swap intel gcc
#module load mkl python
#module load mkl mpt python
#module load intel mpt
#module add mpiblast 
#module load openmpi

#module load mkl mpiblast python

#module reset
#module swap openmpi
#module swap mvapich2 openmpi
#module load mkl python openmpi


#cd /work/hokieone/ilikeit/057139_000656029
#cp /home/ilikeit/hokieone/waterfall.py .
#cp /home/ilikeit/hokieone/errors.py .
#cp /home/ilikeit/hokieone/drx.py .
#cp /home/ilikeit/hokieone/dp.py .

# Consult https://lwalab.phys.unm.edu/CompScreen/cs.php
HOSTS=lwaucf2,lwaucf4,lwaucf5
PROCS=5

INDIR=/data/network/recent_data/jtsai
INFILE=057974_001488585
WORKDIR=/mnt/toaster/cleague/work1b
CODEDIR=$HOME/Radio-Transient-Search

export PYTHONPATH=$CODEDIR:

mkdir -p $WORKDIR
mpirun -host $HOSTS -npernode 1 mkdir -v -p $WORKDIR
cd $WORKDIR
mpirun -host $HOSTS -npernode 1 ln -svf $INDIR/$INFILE .
time mpirun -host $HOSTS -np $PROCS -x PYTHONPATH python $CODEDIR/waterfall.py $INFILE |& tee runlog.$$

