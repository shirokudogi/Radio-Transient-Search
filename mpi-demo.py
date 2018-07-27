from mpi4py import MPI
import time

comm = MPI.COMM_WORLD
steps = 0

def worker(task):
    a, b = task
    global steps
    steps += 1
    print comm.Get_rank(),
    if comm.Get_rank() % 2 == 0:
        time.sleep(0.000)
    return a**2 + b**2

def main(pool):
    # Here we generate some fake data
    import random
    a = [random.random() for _ in range(1000)]
    b = [random.random() for _ in range(1000)]

    tasks = list(zip(a, b))
    results = pool.map(worker, tasks)
    pool.close()

    print(results[:8])

if __name__ == "__main__":
    import sys
    from schwimmbad import MPIPool

    pool = MPIPool()

    if not pool.is_master():
        pool.wait()
        print "\nProc %d: %d steps" % (comm.Get_rank(), steps)
        sys.exit(0)

    main(pool)
