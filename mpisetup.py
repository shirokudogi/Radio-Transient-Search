from mpi4py import MPI
import socket
import time

comm  = MPI.COMM_WORLD
totalrank = comm.Get_size()
rank = comm.Get_rank()
host = socket.gethostname()
t0 = time.time()

def log(message):
    print '%d:%s:%.03f: %s' % (rank, host, time.time() - t0, message)

