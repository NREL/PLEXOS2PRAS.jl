function extract_modelname(filename::String,
                           suffix::String,
                           default::String="system")::String

    rgx = Regex(".*Model (.+)_" * suffix * " Solution.*")
    result = match(rgx, filename)

    if result isa Void
        warn("Could not determine PLEXOS model name from filename $filename, " *
             "falling back on default '$default'")
        return  default
    else
        return result.captures[1]
    end

end
