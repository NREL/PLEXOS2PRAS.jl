#! /usr/bin/sh

# Download the environment file
wget -O plexos2pras_env.yml https://github.nrel.gov/raw/PRAS/PLEXOS2PRAS/v0.2.0/environment.yml

# Install and activate the environment
module load conda
conda env update -f plexos2pras_env.yml
source activate plexos2pras

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
julia -e 'Pkg.clone("https://github.nrel.gov/PRAS/ResourceAdequacy.jl.git"); using ResourceAdequacy'


# Install PLEXOS2PRAS Julia dependencies,
# necessary because the Julia scripts live inside a Python module,
# so no REQUIRE file gets resolved
julia -e 'Pkg.add("HDF5"); Pkg.add("JLD"); Pkg.add("DataFrames"); Pkg.add("PyCall"); using HDF5; using JLD; using DataFrames; using PyCall'
