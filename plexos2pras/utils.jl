function extract_modelname(filename::String,
                           suffix::String,
                           default::String="system")::String

    rgx = Regex(".*Model (.+)_" * suffix * " Solution.*")
    result = match(rgx, filename)
    return result isa Void ? default : result.captures[1]

end
