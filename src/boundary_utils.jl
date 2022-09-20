#=
Utilities used by the generated solve() functions for handling boundary conditions.
=#

# Returns the matrix operator for norm dot grad for each face node (other rows are zero)
# For edge/vertex nodes, the bid assigned to the node determines the face, but if
# the bid matches multiple faces, the choice is not guaranteed.
function get_norm_dot_grad(eid::Int, grid::Grid, refel::Refel, geometric_factors::GeometricFactors)
    nnodes = refel.Np;
    dim = refel.dim;
    # Will need all the the Ddr derivative matrices for this element
    RD1 = zeros(Float64, nnodes, nnodes);
    build_derivative_matrix(refel, geometric_factors, 1, eid, 1, RD1);
    if dim > 1
        RD2 = zeros(Float64, nnodes, nnodes);
        build_derivative_matrix(refel, geometric_factors, 2, eid, 1, RD2);
    end
    if dim > 2
        RD3 = zeros(Float64, nnodes, nnodes);
        build_derivative_matrix(refel, geometric_factors, 3, eid, 1, RD3);
    end
    
    # The result will be this
    ndotgrad = zeros(nnodes,nnodes);
    
    # Match each node to a face
    nid = zeros(Int, nnodes);
    nbid = zeros(Int, nnodes);
    # First fill this with the bid of each node
    for ni=1:nnodes
        nid[ni] = grid.loc2glb[ni, eid];
        nbid[ni] = grid.nodebid[nid[ni]];
    end
    # Loop over faces of this element
    for fi=1:refel.Nfaces
        fid = grid.element2face[fi, eid];
        fbid = grid.facebid[fid];
        if fbid > 0
            fnorm = grid.facenormals[:,fid];
            for fni = 1:refel.Nfp[fi] # for nodes on this face
                for ni=1:nnodes # for nodes in this element
                    if nid[ni] == grid.face2glb[fni, 1, fid]
                        # This ni corresponds to this fni
                        # make sure bid is the same
                        if fbid == nbid[ni]
                            # It's a match
                            # row ni in the matrix will be set
                            for col = 1:nnodes
                                if dim == 1
                                    ndotgrad[ni, col] = RD1[ni, col] * fnorm[1];
                                elseif dim == 2
                                    ndotgrad[ni, col] = RD1[ni, col] * fnorm[1] + RD2[ni, col] * fnorm[2];
                                elseif dim == 3
                                    ndotgrad[ni, col] = RD1[ni, col] * fnorm[1] + RD2[ni, col] * fnorm[2] + RD3[ni, col] * fnorm[3];
                                end
                            end
                        end
                        break;
                    end
                end
            end
        end
    end
    
    return ndotgrad;
end

# This evaluates the BC at a specific node.
# That could mean:
# - the value of constant BCs
# - evaluate a genfunction.func for BCs defined by strings->genfunctions
# - evaluate a function for BCs defined by callback functions
function evaluate_at_nodes(val, nodes, face, t)
    N = length(nodes);
    dim = config.dimension;
    if typeof(val) <: Number
        result = fill(val, N);
        
    elseif typeof(val) == Coefficient && typeof(val.value[1]) == GenFunction
        result = zeros(N);
        if dim == 1
            for i=1:N
                result[i]=val.value[1].func(grid_data.allnodes[1,nodes[i]],0,0,t,nodes[i],face);
            end
        elseif dim == 2
            for i=1:N
                result[i]=val.value[1].func(grid_data.allnodes[1,nodes[i]],grid_data.allnodes[2,nodes[i]],0,t,nodes[i],face);
            end
        else
            for i=1:N
                result[i]=val.value[1].func(grid_data.allnodes[1,nodes[i]],grid_data.allnodes[2,nodes[i]],grid_data.allnodes[3,nodes[i]],t,nodes[i],face);
            end
        end
        
    elseif typeof(val) == GenFunction
        result = zeros(N);
        if dim == 1
            for i=1:N
                result[i]=val.func(grid_data.allnodes[1,nodes[i]],0,0,t,nodes[i],face);
            end
        elseif dim == 2
            for i=1:N
                result[i]=val.func(grid_data.allnodes[1,nodes[i]],grid_data.allnodes[2,nodes[i]],0,t,nodes[i],face);
            end
        else
            for i=1:N
                result[i]=val.func(grid_data.allnodes[1,nodes[i]],grid_data.allnodes[2,nodes[i]],grid_data.allnodes[3,nodes[i]],t,nodes[i],face);
            end
        end
        
    elseif typeof(val) == CallbackFunction
        result = zeros(N);
        for i=1:N
            #form a dict for the arguments. x,y,z,t are always included
            arg_list = [];
            append!(arg_list, [("x", grid_data.allnodes[1,nodes[i]]),
                        ("y", dim>1 ? grid_data.allnodes[2,nodes[i]] : 0),
                        ("z", dim>2 ? grid_data.allnodes[3,nodes[i]] : 0),
                        ("t", t)]);
            # Add in the requires list
            for r in val.args
                foundit = false;
                # is it an entity?
                if typeof(r) == Variable
                    foundit = true;
                    if size(r.values,1) == 1
                        push!(arg_list, (string(r.symbol), r.values[1,nodes[i]]));
                    else
                        push!(arg_list, (string(r.symbol), r.values[:,nodes[i]]));
                    end
                elseif typeof(r) == Coefficient
                    # TODO: evaluate coefficient at node
                    foundit = true;
                    push!(arg_list, (string(r.symbol), evaluate_at_nodes(r, nodes[i], face, t)));
                elseif typeof(r) == String
                    # This could also be a variable, coefficient, or special thing like normal, 
                    if r in ["x","y","z","t"]
                        foundit = true;
                        # These are already included
                    elseif r == "normal"
                        foundit = true;
                        push!(arg_list, ("normal", grid_data.facenormals[:,face]));
                    else
                        for v in variables
                            if string(v.symbol) == r
                                foundit = true;
                                if size(v.values,1) == 1
                                    push!(arg_list, (r, v.values[1,nodes[i]]));
                                else
                                    push!(arg_list, (r, v.values[:,nodes[i]]));
                                end
                                break;
                            end
                        end
                        for c in coefficients
                            if string(c.symbol) == r
                                foundit = true;
                                push!(arg_list, (r, evaluate_at_nodes(c, nodes[i], face, t)));
                                break;
                            end
                        end
                    end
                else
                    # What else could it be?
                end

                if !foundit
                    # Didn't figure this thing out.
                    printerr("Unknown requirement for callback function "*string(fun)*" : "*string(requires[i]));
                end
            end
            
            # Build the dict
            args = Dict(arg_list);
            
            # call the function
            result[i] = val.func(args);
        end
        
    end
    return result;
end

# This evaluates the BC at one specific node.
# That could mean:
# - the value of constant BCs
# - evaluate a genfunction.func for BCs defined by strings->genfunctions
# - evaluate a function for BCs defined by callback functions
function evaluate_at_node(val, node::Int, face::Int, t::Union{Int, Float64}, grid::Grid)
    if typeof(val) <: Number
        return val;
    end
    
    dim = size(grid.allnodes,1);
    result = 0;
    x = grid.allnodes[1,node];
    y = dim > 1 ? grid.allnodes[2,node] : 0;
    z = dim > 2 ? grid.allnodes[3,node] : 0;
        
    if typeof(val) == Coefficient && typeof(val.value[1]) == GenFunction
        result = val.value[1].func(x,y,z,t,node,face);
        
    elseif typeof(val) == GenFunction
        result = val.func(x,y,z,t,node,face);
        
    elseif typeof(val) == CallbackFunction
        #form a dict for the arguments. x,y,z,t are always included
        arg_list = [];
        append!(arg_list, [("x", x), ("y", y), ("z", z), ("t", t)]);
        # Add in the requires list
        for r in val.args
            foundit = false;
            # is it an entity?
            if typeof(r) == Variable
                foundit = true;
                if size(r.values,1) == 1
                    push!(arg_list, (string(r.symbol), r.values[1,node]));
                else
                    push!(arg_list, (string(r.symbol), r.values[:,node]));
                end
            elseif typeof(r) == Coefficient
                # TODO: evaluate coefficient at node
                foundit = true;
                push!(arg_list, (string(r.symbol), evaluate_at_node(r, node, face, t, grid)));
            elseif typeof(r) == String
                # This could also be a variable, coefficient, or special thing like normal, 
                if r in ["x","y","z","t"]
                    foundit = true;
                    # These are already included
                elseif r == "normal"
                    foundit = true;
                    push!(arg_list, ("normal", grid.facenormals[:,face]));
                else
                    for v in variables
                        if string(v.symbol) == r
                            foundit = true;
                            if size(v.values,1) == 1
                                push!(arg_list, (r, v.values[1,node]));
                            else
                                push!(arg_list, (r, v.values[:,node]));
                            end
                            break;
                        end
                    end
                    for c in coefficients
                        if string(c.symbol) == r
                            foundit = true;
                            push!(arg_list, (r, evaluate_at_nodes(c, node, face, t)));
                            break;
                        end
                    end
                end
            else
                # What else could it be?
            end

            if !foundit
                # Didn't figure this thing out.
                printerr("Unknown requirement for callback function "*string(fun)*" : "*string(r));
            end
        end
        
        # Build the dict
        args = Dict(arg_list);
        
        # call the function
        result = val.func(args);
        
    end
    return result;
end

# This evaluates the BC at a specific face for FV.
# That could mean:
# - the value of constant BCs
# - evaluate a genfunction.func for BCs defined by strings->genfunctions
# - evaluate a function for BCs defined by callback functions
function FV_evaluate_bc(val, eid, fid, t)
    dim = config.dimension;
    if typeof(val) <: Number
        result = val;
        
    elseif typeof(val) == Coefficient 
        facex = fv_info.faceCenters[:,fid];
        result = evaluate_coefficient(val, 1, facex, t, eid, fid);
        
    elseif typeof(val) == GenFunction
        facex = fv_info.faceCenters[:,fid];
        if dim == 1
            result=val.func(facex[1],0,0,t,eid,fid);
        elseif dim == 2
            result=val.func(facex[1],facex[2],0,t,eid,fid);
        else
            result=val.func(facex[1],facex[2],facex[3],t,eid,fid);
        end
        
    elseif typeof(val) == CallbackFunction
        facex = fv_info.faceCenters[:,fid];
        #form a dict for the arguments. x,y,z,t are always included
        arg_list = [];
        append!(arg_list, [("x", facex[1]),
                    ("y", dim>1 ? facex[2] : 0),
                    ("z", dim>2 ? facex[3] : 0),
                    ("t", t)]);
        # Add in the requires list
        for r in val.args
            foundit = false;
            # is it an entity?
            if typeof(r) == Variable
                foundit = true;
                if size(r.values,1) == 1
                    push!(arg_list, (string(r.symbol), r.values[1,eid]));
                else
                    push!(arg_list, (string(r.symbol), r.values[:,eid]));
                end
            elseif typeof(r) == Coefficient
                foundit = true;
                cvals = zeros(size(r.value));
                facex = fv_info.faceCenters[:,fid];
                for i=1:length(cvals)
                    cvals[i] = evaluate_coefficient(r, i, facex, t, eid, fid);
                end
                push!(arg_list, (string(r.symbol), cvals));
            elseif typeof(r) == Indexer
                foundit = true;
                push!(arg_list, (string(r.symbol), r.value));
            elseif typeof(r) == String
                # This could also be a variable, coefficient, or special thing like normal, 
                if r in ["x","y","z","t"]
                    foundit = true;
                    # These are already included
                elseif r == "normal"
                    foundit = true;
                    push!(arg_list, ("normal", fv_grid.facenormals[:,fid]));
                else
                    for v in variables
                        if string(v.symbol) == r
                            foundit = true;
                            if size(v.values,1) == 1
                                push!(arg_list, (r, v.values[1,eid]));
                            else
                                push!(arg_list, (r, v.values[:,eid]));
                            end
                            break;
                        end
                    end
                    for c in coefficients
                        if string(c.symbol) == r
                            foundit = true;
                            push!(arg_list, (r, FV_evaluate_bc(c, eid, fid, t)));
                            break;
                        end
                    end
                end
            else
                # What else could it be?
            end

            if !foundit
                # Didn't figure this thing out.
                printerr("Unknown requirement for callback function "*string(fun)*" : "*string(requires[i]));
            end
        end
        
        # Build the dict
        args = Dict(arg_list);
        
        # call the function
        result = val.func(args);
        
    end
    return result;
end

#######################################################################################################################
## Functions for applying boundary conditions
#######################################################################################################################

# Apply boundary conditions to one element
function apply_boundary_conditions_elemental(var::Vector{Variable}, eid::Int, grid::Grid, refel::Refel,
                                            geo_facs::GeometricFactors, prob::Finch_prob, t::Union{Int,Float64},
                                            elmat::Matrix{Float64}, elvec::Vector{Float64}, bdry_done::Vector{Int},
                                            component::Int = 0)
    # Check each node to see if the bid is > 0 (on boundary)
    nnodes = refel.Np;
    norm_dot_grad = nothing;
    for ni=1:nnodes
        node_id = grid.loc2glb[ni,eid];
        node_bid = grid.nodebid[node_id];
        face_id = -1; # This may need to be figured out, but it is not clear which face for vertices
        if node_bid > 0
            # This is a boundary node in node_bid
            # Handle the BC for each variable
            row_index = ni;
            col_offset = 0;
            for vi=1:length(var)
                if !(var[1].indexer === nothing)
                    compo_range = component + 1;
                    # row_index += nnodes * (component-1);
                    # col_offset += nnodes * (component-1);
                else
                    compo_range = 1:var[vi].total_components;
                end
                for compo=compo_range
                    bc_type = prob.bc_type[var[vi].index, node_bid];
                    if bc_type == NO_BC
                        # do nothing
                    elseif bc_type == DIRICHLET
                        # zero the row
                        for nj=1:size(elmat,2)
                            elmat[row_index, nj] = 0;
                        end
                        elvec[row_index] = 0;
                        if (bdry_done[node_id] == 0 || bdry_done[node_id] == eid)
                            # elmat row is identity
                            elmat[row_index, row_index] = 1;
                            # elvec row is value
                            elvec[row_index] = evaluate_at_node(prob.bc_func[var[vi].index, node_bid][compo], node_id, face_id, t, grid);
                        end
                        
                    elseif bc_type == NEUMANN
                        # zero the row
                        for nj=1:size(elmat,2)
                            elmat[row_index, nj] = 0;
                        end
                        elvec[row_index] = 0;
                        if (bdry_done[node_id] == 0 || bdry_done[node_id] == eid)
                            # elmat row is grad dot norm
                            if norm_dot_grad === nothing
                                # This only needs to be made once per element
                                norm_dot_grad = get_norm_dot_grad(eid, grid, refel, geo_facs);
                            end
                            for nj = 1:nnodes
                                elmat[row_index, col_offset+nj] = norm_dot_grad[ni, nj];
                            end
                            # elvec row is value
                            elvec[row_index] = evaluate_at_node(prob.bc_func[var[vi].index, node_bid][compo], node_id, face_id, t, grid);
                        end
                    elseif bc_type == ROBIN
                        printerr("Robin BCs not ready.");
                    else
                        printerr("Unsupported boundary condition type: "*bc_type);
                    end
                    
                    row_index += nnodes;
                    col_offset += nnodes;
                end
            end
            
            # Set the flag to done
            bdry_done[node_id] = eid;
        end
    end
end

# Apply boundary conditions to one element
function apply_boundary_conditions_elemental_rhs(var::Vector{Variable}, eid::Int, grid::Grid, refel::Refel,
                                            geo_facs::GeometricFactors, prob::Finch_prob, t::Union{Int,Float64},
                                            elvec::Vector{Float64}, bdry_done::Vector{Int}, component::Int = 0)
    # Check each node to see if the bid is > 0 (on boundary)
    nnodes = refel.Np;
    for ni=1:nnodes
        node_id = grid.loc2glb[ni,eid];
        node_bid = grid.nodebid[node_id];
        face_id = -1; # This may need to be figured out, but it is not clear which face for vertices
        if node_bid > 0
            # This is a boundary node in node_bid
            # Handle the BC for each variable
            row_index = ni;
            for vi=1:length(var)
                if !(var[1].indexer === nothing)
                    compo_range = component + 1;
                    # row_index += nnodes * (component-1);
                else
                    compo_range = 1:var[vi].total_components;
                end
                for compo=compo_range
                    bc_type = prob.bc_type[var[vi].index, node_bid];
                    if bc_type == NO_BC
                        # do nothing
                    elseif bc_type == DIRICHLET
                        elvec[row_index] = 0;
                        if (bdry_done[node_id] == 0 || bdry_done[node_id] == eid)
                            # elvec row is value
                            elvec[row_index] = evaluate_at_node(prob.bc_func[var[vi].index, node_bid][compo], node_id, face_id, t, grid);
                        end
                        
                    elseif bc_type == NEUMANN
                        elvec[row_index] = 0;
                        if (bdry_done[node_id] == 0 || bdry_done[node_id] == eid)
                            # elvec row is value
                            elvec[row_index] = evaluate_at_node(prob.bc_func[var[vi].index, node_bid][compo], node_id, face_id, t, grid);
                        end
                    elseif bc_type == ROBIN
                        printerr("Robin BCs not ready.");
                    else
                        printerr("Unsupported boundary condition type: "*bc_type);
                    end
                    
                    row_index += nnodes;
                end
            end
            
            # Set the flag to done
            bdry_done[node_id] = eid;
        end
    end
end

function apply_boundary_conditions_face(var::Vector{Variable}, eid::Int, fid::Int, fbid::Int, mesh::Grid, refel::Refel, 
                                        geometric_factors::GeometricFactors, prob::Finch_prob, t::Union{Int,Float64}, 
                                        flux_mat::Matrix{Float64}, flux_vec::Vector{Float64}, bdry_done::Vector{Int}, 
                                        component::Int = 0)
    dofind = 0;
    for vi=1:length(var)
        if !(var[1].indexer === nothing)
            compo_range = component + 1;
            # row_index += nnodes * (component-1);
        else
            compo_range = 1:var[vi].total_components;
        end
        for compo=compo_range
            dofind = dofind + 1;
            if prob.bc_type[var[vi].index, fbid] == NO_BC
                # do nothing
            elseif prob.bc_type[var[vi].index, fbid] == FLUX
                # compute the value and add it to the flux directly
                # Qvec = (refel.surf_wg[fv_grid.faceRefelInd[1,fid]] .* fv_geo_factors.face_detJ[fid])' * (refel.surf_Q[fv_grid.faceRefelInd[1,fid]])[:, refel.face2local[fv_grid.faceRefelInd[1,fid]]]
                # Qvec = Qvec ./ fv_geo_factors.area[fid];
                # bflux = FV_flux_bc_rhs_only(prob.bc_func[var[vi].index, fbid][compo], facex, Qvec, t, dofind, dofs_per_node) .* fv_geo_factors.area[fid];
                flux_vec[dofind] = FV_evaluate_bc(prob.bc_func[var[vi].index, fbid][compo], eid, fid, t);
                # for i=1:size(flux_mat,2)
                #     flux_mat[dofind, i] = 0;
                # end
                
            elseif prob.bc_type[var[vi].index, fbid] == DIRICHLET
                # Set variable array and handle after the face loop
                var[vi].values[compo,eid] = FV_evaluate_bc(prob.bc_func[var[vi].index, fbid][compo], eid, fid, t);
                # for i=1:size(flux_mat,2)
                #     flux_mat[dofind, i] = 0;
                # end
                
            else
                printerr("Unsupported boundary condition type: "*prob.bc_type[var[vi].index, fbid]);
            end
        end
    end
end

# A RHS only version of above
# Modify the flux vector
function apply_boundary_conditions_face_rhs(var::Vector{Variable}, eid::Int, fid::Int, fbid::Int, mesh::Grid, refel::Refel, 
                                            geometric_factors::GeometricFactors, prob::Finch_prob, t::Union{Int,Float64}, 
                                            flux::Vector{Float64}, bdry_done::Vector{Int}, component::Int = 0)
    dofind = 0;
    for vi=1:length(var)
        if !(var[1].indexer === nothing)
            compo_range = component + 1;
            # row_index += nnodes * (component-1);
        else
            compo_range = 1:var[vi].total_components;
        end
        for compo=compo_range
            dofind = dofind + 1;
            if prob.bc_type[var[vi].index, fbid] == NO_BC
                # do nothing
            elseif prob.bc_type[var[vi].index, fbid] == FLUX
                # compute the value and add it to the flux directly
                # Qvec = (refel.surf_wg[fv_grid.faceRefelInd[1,fid]] .* fv_geo_factors.face_detJ[fid])' * (refel.surf_Q[fv_grid.faceRefelInd[1,fid]])[:, refel.face2local[fv_grid.faceRefelInd[1,fid]]]
                # Qvec = Qvec ./ fv_geo_factors.area[fid];
                # bflux = FV_flux_bc_rhs_only(prob.bc_func[var[vi].index, fbid][compo], facex, Qvec, t, dofind, dofs_per_node) .* fv_geo_factors.area[fid];
                flux[dofind] = FV_evaluate_bc(prob.bc_func[var[vi].index, fbid][compo], eid, fid, t);
                # if !is_explicit
                #     bflux = bflux .* dt;
                # end
                
            elseif prob.bc_type[var[vi].index, fbid] == DIRICHLET
                # Set variable array and handle after the face loop
                var[vi].values[compo,eid] = FV_evaluate_bc(prob.bc_func[var[vi].index, fbid][compo], eid, fid, t);
                # If implicit, this needs to be handled before solving
                # if !is_explicit
                #     #TODO
                # end
            else
                printerr("Unsupported boundary condition type: "*prob.bc_type[var[vi].index, fbid]);
            end
        end
    end
end
