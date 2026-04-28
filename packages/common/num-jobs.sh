# Memory required per job in bytes (default 2GB)
MEM_PER_JOB=${1:-$((2 * 1024 * 1024 * 1024))}

# Total available memory in bytes (Linux)
# MemAvailable might be a better metric, but MSYS2 doesn't have it
TOTAL_MEM=$(awk '/MemTotal/ { print $2 * 1024 }' /proc/meminfo)

# Number of processors
NUM_PROCS=$(nproc)

# Jobs limited by memory
MEM_JOBS=$(( TOTAL_MEM / MEM_PER_JOB ))

# Use the lesser of the two, minimum 1
PARALLEL_JOBS=$(( MEM_JOBS < NUM_PROCS ? MEM_JOBS : NUM_PROCS ))
PARALLEL_JOBS=$(( PARALLEL_JOBS < 1 ? 1 : PARALLEL_JOBS ))

echo "-- Parallel jobs: $PARALLEL_JOBS" >&2
export MAKEFLAGS="-j$PARALLEL_JOBS"
