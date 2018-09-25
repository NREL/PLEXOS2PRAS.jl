#! /usr/bin/sh

# Download the environment file
wget -O plexos2pras_env.yml https://github.nrel.gov/raw/PRAS/PLEXOS2PRAS/master/environment.yml

# Install and activate the environment
module load conda
conda env update -f plexos2pras_env.yml
source activate plexos2pras

# Add process-solutions alias when entering environment
pythoncode='
import os; import inspect; import plexos2pras
print(os.path.dirname(inspect.getfile(plexos2pras)))'
scriptpath=$(python -c "$pythoncode")
mkdir -p $CONDA_PREFIX/etc/conda/activate.d
echo "alias process-solutions='julia -p auto "$scriptpath"/process_solutions.jl'" > \
    $CONDA_PREFIX/etc/conda/activate.d/set_alias.sh

# Remove process-solutions alias when leaving environment
mkdir -p $CONDA_PREFIX/etc/conda/deactivate.d
echo "unalias process-solutions" > $CONDA_PREFIX/etc/conda/deactivate.d/unset_alias.sh

# Set up custom PRAS dependencies
julia_pkg_dir=$(julia -e 'println(Pkg.dir())')
julia -e 'Pkg.add("Distributions"); Pkg.add("LightGraphs")'

cd $julia_pkg_dir/Distributions
git remote add gs-fork https://github.com/GordStephen/Distributions.jl.git
git fetch gs-fork
git checkout gs-fork/gs/all-updates

cd $julia_pkg_dir/LightGraphs
git remote add gs-fork https://github.com/GordStephen/LightGraphs.jl.git
git fetch gs-fork
git checkout gs-fork/gs/inplace-maxflows

julia -e 'Pkg.resolve()'

# Install PRAS
# This assumes you have access to the private GitHub.com repo
# with SSH keys configured appropriately
julia -e 'Pkg.clone("git@github.com:NREL/ResourceAdequacy.jl.git"); using ResourceAdequacy'

# Install PLEXOS2PRAS Julia dependencies,
# necessary because the Julia scripts live inside a Python module,
# so no REQUIRE file gets resolved
julia -e 'Pkg.add("ArgParse"); Pkg.add("HDF5"); Pkg.add("JLD"); Pkg.add("DataFrames"); Pkg.add("PyCall")'
julia -e 'using ArgParse; using HDF5; using JLD; using DataFrames; using PyCall'
