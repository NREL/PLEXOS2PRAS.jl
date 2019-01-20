struct RawSystemData{T<:Period,V<:Real}

    timestamps::StepRange{DateTime, T}

    regionnames::Vector{String}
    demand::Matrix{V}

    vgregions::Vector{Int}
    vgcapacity::Matrix{V}

    dispregions::Vector{Int}
    dispcapacity::Matrix{V}
    dispoutagerate::Matrix{V}
    dispmttr::Matrix{V}

    interfaceregions::Vector{Tuple{Int,Int}}
    interfacecapacity::Matrix{V}

    lineregions::Vector{Tuple{Int,Int}}
    linecapacity::Matrix{V}
    lineoutagerate::Matrix{V}
    linemttr::Matrix{V}

    function RawSystemData{}(
        timestamps::StepRange{DateTime,T},
        regionnames::Vector{String},
        demand::Matrix{V},
        vgregions::Vector{Int},
        vgcapacity::Matrix{V},
        dispregions::Vector{Int},
        dispcapacity::Matrix{V},
        dispoutagerate::Matrix{V},
        dispmttr::Matrix{V},
        interfaceregions::Vector{Tuple{Int,Int}},
        interfacecapacity::Matrix{V},
        lineregions::Vector{Tuple{Int,Int}},
        linecapacity::Matrix{V},
        lineoutagerate::Matrix{V},
        linemttr::Matrix{V}) where {T<:Period, V<:Real}

        n_periods = length(timestamps)
        n_regions = length(regionnames)
        n_vg = length(vgregions)
        n_disp = length(dispregions)
        n_interfaces = length(interfaceregions)
        n_lines = length(lineregions)

        @assert size(demand) == (n_periods, n_regions)

        @assert size(vgcapacity) == (n_periods, n_vg)

        @assert size(dispcapacity) == (n_periods, n_disp)
        @assert size(dispoutagerate) == (n_periods, n_disp)
        @assert size(dispmttr) == (n_periods, n_disp)

        @assert size(interfacecapacity) == (n_periods, n_interfaces)

        @assert size(linecapacity) == (n_periods, n_lines)
        @assert size(lineoutagerate) == (n_periods, n_lines)
        @assert size(linemttr) == (n_periods, n_lines)

        reorder!(vgregions, vgcapacity)
        reorder!(dispregions, dispcapacity, dispoutagerate, dispmttr)
        reorder!(interfaceregions, interfacecapacity)
        reorder!(lineregions, linecapacity, lineoutagerate, linemttr)

        new{T,V}(timestamps, regionnames, demand,
                 vgregions, vgcapacity,
                 dispregions, dispcapacity, dispoutagerate, dispmttr,
                 interfaceregions, interfacecapacity,
                 lineregions, linecapacity, lineoutagerate, linemttr)

    end

end

"Reorder key list and data matrix columns, sorting by keys"
function reorder!(keys::Vector, matrices::Matrix{V}...) where {V<:Real}

    neworder = sortperm(keys)
    permute!(keys, neworder)
    old_matrix = similar(matrices[1])

    for matrix in matrices
        copy!(old_matrix, matrix)
        for (new_col, old_col) in enumerate(neworder)
            matrix[:, new_col] = old_matrix[:, old_col]
        end
    end

end

