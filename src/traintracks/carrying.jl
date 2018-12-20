
module Carrying

export CarryingMap, cusp_nextto_branch

using Donut.TrainTracks
using Donut.TrainTracks: numswitches_if_made_trivalent, numbranches_if_made_trivalent
using Donut.TrainTracks.Cusps

struct CarryingMap
    large_tt::TrainTrack
    small_tt::TrainTrack
    large_cusphandler::CuspHandler
    small_cusphandler::CuspHandler
    small_cusp_to_large_cusp::Vector{Int} # [small cusps] 
    large_cusp_to_small_cusp::Vector{Int} # [large cusps]
    extremal_intervals::Array{Int, 2}  #  [LEFT,RIGHT] x [large switches]
    interval_to_click::Array{Int, 2} # [LEFT, RIGHT] x [intervals]
    click_to_interval::Array{Int, 2} # [LEFT, RIGHT] x [clicks]
    small_switch_to_click::Vector{Int} # [small switches]
    interval_to_large_switch::Vector{Int}  # [intervals]
    click_to_small_switch::Vector{Int} # [clicks]
    unused_interval_indices::Vector{Int}
    unused_click_indices::Vector{Int}
    paths::Array{BigInt, 2} # [large branches x intervals] x [small branches + cusp paths]
    temp_intersections::Array{BigInt, 2} # 2 x [small branches + cusp paths]   (2 temporary paths)
    temp_paths::Array{BigInt, 2} # [large branches x intervals] x 2
    cusp_index_offset::Int
    interval_index_offset::Int

    """
    A train track carrying itself.
    """
    function CarryingMap(tt::TrainTrack, ch::CuspHandler)
        numsw = numswitches_if_made_trivalent(tt)
        numbr = numbranches_if_made_trivalent(tt)
        # ncusps = numcusps(tt)

        ncusps = max_cusp_number(ch)

        small_cusp_to_large_cusp = zeros(Int, ncusps)
        large_cusp_to_small_cusp = zeros(Int, ncusps)

        for cusp in cusps(ch)
            small_cusp_to_large_cusp[cusp] = cusp
            large_cusp_to_small_cusp[cusp] = cusp
        end

        extremal_intervals = zeros(Int, 2, numsw)
        interval_to_click = zeros(Int, 2, 2*numsw)
        click_to_interval = zeros(Int, 2, numsw)
        small_switch_to_click = zeros(Int, numsw)
        interval_to_large_switch = zeros(Int, 2*numsw)
        click_to_small_switch = zeros(Int, numsw)

        i = 1
        for sw in switches(tt)
            @assert sw == i
            extremal_intervals[LEFT, i] = 2*i-1
            extremal_intervals[RIGHT, i] = 2*i
            interval_to_click[LEFT, 2*i-1] = 0
            interval_to_click[RIGHT, 2*i-1] = i
            click_to_interval[LEFT, i] = 2*i-1
            interval_to_click[LEFT, 2*i] = i
            click_to_interval[RIGHT, i] = 2*i
            interval_to_click[RIGHT, 2*i] = 0

            small_switch_to_click[sw] = i
            interval_to_large_switch[2*i-1] = i
            interval_to_large_switch[2*i] = i
            click_to_small_switch[i] = sw
            i += 1
        end
        unused_interval_indices = collect(Int, 2*numsw : -1 : 2*i-1)
        unused_click_indices = Int[]

        paths = zeros(BigInt, numbr + 2*numsw, numbr + ncusps)
        temp_intersections = zeros(BigInt, 2, numbr + ncusps)
        temp_paths = zeros(BigInt, numbr + 2*numsw, 1)

        for br in branches(tt)
            paths[br, br] = 1
        end

        cusp_index_offset = numsw
        interval_index_offset = numbr

        new(tt, copy(tt), ch, copy(ch),
        small_cusp_to_large_cusp, large_cusp_to_small_cusp, 
        extremal_intervals, interval_to_click, click_to_interval 
        small_switch_to_click, interval_to_large_switch, click_to_small_switch, 
        unused_interval_indices, unused_click_indices, paths, temp_intersections,
        temp_paths, cusp_index_offset, interval_index_offset)
    end
end

small_cusp_to_large_cusp(cm::CarryingMap, small_cusp::Int) = cm.small_cusp_to_large_cusp[small_cusp]
large_cusp_to_small_cusp(cm::CarryingMap, large_cusp::Int) = cm.large_cusp_to_small_cusp[large_cusp]


BRANCH = 0
CUSP = 1
INTERVAL = 1
TEMP = 2

branch_or_cusp_to_index(cm::CarryingMap, branch_or_cusp::Int, label::Int) = 
branch_or_cusp == CUSP ? abs(label) + cm.cusp_index_offset : abs(label)

branch_or_interval_to_index(cm::CarryingMap, branch_or_interval::Int, label::Int) = 
    branch_or_interval == INTERVAL ? abs(label) + cm.interval_index_offset : abs(label)



function add_paths_small!(cm::CarryingMap, branch_or_cusp1::Int, add_to_label::Int, 
    branch_or_cusp2::Int, added_label::Int, with_sign::Int=1)
    idx1 = branch_or_cusp_to_index(branch_or_cusp1, append_to_label)
    idx2 = branch_or_cusp_to_index(branch_or_cusp2, appended_label)
    arr1 = branch_or_cusp1 == TEMP ? cm.temp_paths : cm.paths
    arr2 = branch_or_cusp2 == TEMP ? cm.temp_paths : cm.paths
    for i in eachindex(size(cm.paths)[1])
        arr1[i, idx1] += with_sign*arr2[i, idx2]
    end
end

function add_paths_large!(cm::CarryingMap, branch_interval_or_temp1::Int, add_to_label::Int, 
    branch_interval_or_temp2::Int, added_label::Int, with_sign::Int=1)
    idx1 = branch_or_interval_to_index(branch_interval_or_temp1, add_to_label)
    idx2 = branch_or_interval_to_index(branch_interval_or_temp2, added_label)
    arr1 = branch_interval_or_temp1 == TEMP ? cm.temp_intersections : cm.paths
    arr2 = branch_interval_or_temp2 == TEMP ? cm.temp_intersections : cm.paths
    for i in eachindex(size(cm.paths)[2])
        arr1[idx1, i] += with_sign * arr2[idx2, i]
    end
end

function add_intersection!(cm::CarryingMap, branch_or_cusp::Int, label::Int, branch_interval_or_temp::Int, label2::Int, with_sign::Int=1)
    idx1 = branch_or_cusp_to_index(branch_or_cusp, label)
    idx2 = branch_or_interval_to_index(branch_interval_or_temp, label2)
    arr = branch_interval_or_temp == TEMP ? cm.temp_intersections : cm.paths
    arr[idx2, idx1] += with_sign
end

function click_to_large_switch(cm::CarryingMap, click::Int)
    interval_to_large_switch(cm, click_to_interval(cm, click, LEFT))
end

function small_switch_to_large_switch(cm::CarryingMap, sw::Int)
    click = small_switch_to_click(cm, sw)
    click_to_large_switch(cm, click)
end


"""
Return the interval on the specified side of the click containing a switch. A signed interval is returned. The sign is positive of the small switch has the same orientation as the large switch. Otherwise the sign is negative.
"""
function small_switch_to_click(cm::CarryingMap, sw::Int)
    sign(sw) * cm.small_switch_to_click[abs(sw)]
end

function set_small_switch_to_click!(cm::CarryingMap, sw::Int, click::Int)
    cm.small_switch_to_click[abs(sw)] = sign(sw) * click
end

function click_to_small_switch(cm::CarryingMap, click::Int)
    sign(click) * cm.click_to_small_switch[abs(click)]
end

function set_click_to_small_switch!(cm::CarryingMap, click::Int, sw::Int)
    cm.click_to_small_switch[abs(click)] = sign(click) * sw
end



#---------------------------------------------------
# Interval manipulation
#---------------------------------------------------

function interval_to_large_switch(cm::CarryingMap, interval::Int)
    sign(interval) * cm.interval_to_large_switch[abs(interval)]
end

function set_interval_to_large_switch!(cm::CarryingMap, interval::Int, large_sw::Int)
    @assert large_sw == 0 || sign(interval) == sign(large_sw)
    cm.interval_to_large_switch[abs(interval)] = abs(large_sw)
end

function click_to_interval(cm::CarryingMap, click::Int, side::Int)
    return sign(click)*cm.click_to_interval[click > 0 ? side : otherside(side), abs(click)]
end

function set_click_to_interval!(cm::CarryingMap, click::Int, side::Int, new_value::Int)
    cm.click_to_interval[click > 0 ? side : otherside(side), abs(click)] = abs(click)*new_value
end

function interval_to_click(cm::CarryingMap, interval::Int, side::Int)
    return sign(interval)*cm.interval_to_click[interval > 0 ? side : otherside(side), abs(interval)]
end

function set_interval_to_click!(cm::CarryingMap, interval::Int, side::Int, new_value::Int)
    cm.interval_to_click[interval > 0 ? side : otherside(side), abs(interval)] = abs(interval)*new_value
end


function _create_interval!(cm::CarryingMap)
    @assert length(cm.unused_interval_indices) > 0
    return pop!(cm.unused_interval_indices)
end

function _create_click!(cm::CarryingMap)
    @assert length(cm.unused_click_indices) > 0
    return pop!(cm.unused_click_indices)
end

function _delete_interval!(cm::CarryingMap, interval::Int)
    push!(cm.unused_interval_indices, abs(interval))
    set_interval_to_large_switch!(cm, interval, 0)
    set_interval_to_click!(cm, interval, LEFT) = 0
    set_interval_to_click!(cm, interval, RIGHT) = 0

    idx = branch_or_interval_to_index(INTERVAL, interval)
    cm.paths[idx, :] .= 0
end

function _delete_click!(cm::CarryingMap, click::Int)
    push!(cm.unused_interval_indices, abs(interval))
    set_click_to_interval!(cm, click, LEFT) = 0
    set_click_to_interval!(cm, click, RIGHT) = 0
    set_click_to_small_switch!(cm, click, 0)
end

function extremal_interval(cm::CarryingMap, large_sw::Int, side::Int)
    cm.extremal_intervals[large_sw > 0 ? side : otherside(side), abs(large_sw)]
end

function set_extremal_interval!(cm::CarryingMap, large_sw::Int, side::Int, new_value::Int)
    @assert sign(large_sw) == sign(new_value)
    cm.extremal_intervals[large_sw > 0 ? side : otherside(side), abs(large_sw)] = abs(new_value)
end

"""
Insert a click on a specified side of in interval. A new interval is also created 
on the opposite side of the new click.
"""
function insert_click!(cm::CarryingMap, interval::Int, side::Int)
    new_interval = create_interval!(cm)
    new_interval = sign(interval) * new_interval
    new_click = create_click!(cm)
    new_click = sign(interval) * new_click

    next_click = interval_to_click(cm, interval, side)
    large_sw = interval_to_large_switch(cm, interval)
    set_interval_to_large_switch!(cm, new_interval, large_sw)

    set_interval_to_click!(cm, interval, side, new_click)
    set_click_to_interval!(cm, new_click, otherside(side), interval)
    set_click_to_interval!(cm, new_click, side, new_interval)
    set_interval_to_click!(cm, new_interval, otherside(side), new_click)
    set_interval_to_click!(cm, new_interval, side, next_click)
    if next_click != 0
        set_click_to_interval!(cm, next_click, otherside(side), new_interval)
    else
        set_extremal_interval!(cm, large_sw, side, new_interval)
    end
    new_click, new_interval
end

function delete_click_and_merge!(cm::CarryingMap, click::Int, deleted_interval_side::Int)
    side = deleted_interval_side
    interval_deleted = click_to_interval(cm, click, side)
    interval_kept = click_to_interval(cm, click, otherside(side))
    next_click = interval_to_click(cm, interval_deleted, side)

    if next_click != 0
        set_click_to_interval!(cm, next_click, otherside(side), interval_kept)
    else
        large_sw = interval_to_large_switch(cm, interval_kept)
        set_extremal_interval!(cm, large_sw, side, interval_kept)
    end
    set_interval_to_click!(cm, interval_kept, side, next_click)

    # Combining the intersections.
    add_paths_large!(cm, INTERVAL, interval_kept, INTERVAL, interval_deleted)

    _delete_click!(click)
    _delete_interval!(interval_deleted)
end


function get_intersections(cm::CarryingMap, branch_or_cusp::Int, label1::Int, branch_or_interval::Int, label2::Int)
    idx1 = branch_or_cusp_to_index(branch_or_cusp, label1)
    idx2 = branch_or_cusp_to_index(branch_or_interval, label2)
    return cm.paths[idx2, idx1]
end

function is_branch_or_cusp_collapsed(cm::CarryingMap, branch_or_cusp::Int, label::Int)
    for large_br in branches(cm.large_tt)
        if get_intersections(cm, branch_or_cusp, label, BRANCH, large_br) != 0
            return false
        end
    end
    return true
end

# function get_intersections(cm::CarryingMap, branch_or_interval::Int, label::Int)
#     idx2 = branch_or_cusp_to_index(branch_or_interval, label2)
#     return cm.paths[idx2, :]
# end


"""Applies a function for the switches connected to the endpoint of a
branch by collapsed branches.

The specified branch is not allowed to use as a connection. Hence the
switches considered is a component of a click minus a switch.

INPUT:
- ``branch`` -- a branch of the small train track

"""
function apply_to_switches_in_click_after_branch(cm::CarryingMap, branch::Int, fn::Function)
    sw = branch_endpoint(cm.small_tt, branch)
    return apply_to_switches_in_click(cm, sw, fn, -branch)
end


"""Applies a function for the switches of the small train track in the specified click.

The tree of switches in the click is traversed via collapsed branches. If ``illegal_br`` is nonzero, then we are not allowed to traverse that branch and as a result we get the switches in a component of a click minus a switch.

The traversed switches are all oriented in the same direction as the starting switch. 
"""
function apply_to_switches_in_click(cm::CarryingMap, start_sw::Int, fn::Function, illegal_br::Int=0)
    fn(start_sw)
    for sgn in (-1, 1)
        for br in outgoing_branches(cm.small_tt, sgn*start_sw)
            if br != illegal_br && is_branch_or_cusp_collapsed(cm, BRANCH, br)
                end_sw = branch_endpoint(cm.small_tt, br)
                apply_to_switches_in_click(cm, end_sw, fn, -br)
            end
        end
    end
end



"""Update the carrying map after peeling in the small train track
"""
function peel_small!(cm::CarryingMap, switch::Int, side::Int)
    peeled_branch = extremal_branch(cm.small_tt, switch, side)
    thick_branch = extremal_branch(cm.small_tt, -switch, otherside(side))

    is_thick_collapsed = is_branch_or_cusp_collapsed(cm, BRANCH, thick_branch)

    if !is_thick_collapsed
        # if the large branch was collapsed, we could still do the appends,
        # but they would not do anything.
        add_paths_small!(cm, BRANCH, peeled_branch, BRANCH, thick_branch)
    
        cusp_to_append_to = branch_to_cusp(cm.small_tt, cm.small_cusphandler, thick_branch, side)
        add_paths_small!(cm, CUSP, cusp_to_append_to, BRANCH, thick_branch)
    
        is_peeled_collapsed = is_branch_or_cusp_collapsed(cm, BRANCH, peeled_branch)
        click = small_switch_to_click(cm, switch)
        interval = click_to_interval(cm, click, side)
        if !is_peeled_collapsed
            # New intersections with an interval next to the switch are
            # only created when none of the two branches are collapsed.
            add_intersection!(cm, BRANCH, peeled_branch, INTERVAL, abs(interval))
            add_intersection!(cm, CUSP, cusp_to_append_to, INTERVAL, abs(interval))
        else:
            # If the peel_off_of branch is not collapsed, but the peeled branch
            # is, then our click breaks apart after the peeling.
            new_click, new_interval = insert_click!(cm, interval, otherside(side))
            end_sw = branch_endpoint(cm.small_tt, peeled_branch)
            set_click_to_small_switch(cm, new_click, -end_sw)
            apply_to_switches_in_click_after_branch(cm, peeled_branch, sw -> set_small_switch_to_click!(cm, sw, new_click) )
        end
    end

end


function fold_large!(cm::CarryingMap, folded_branch::Int, fold_onto_branch::Int,
    folded_branch_side::Int)
    # Adding the intersections with the folded branch to fold_onto_branch...
    add_paths_large!(cm, BRANCH, fold_onto_branch, BRANCH, folded_branch)

    # ... and also the left- or rightmost interval at the merged switch
    large_sw = branch_endpoint(cm.large_tt, fold_onto_branch)
    # TODO: twisted branch
    interval = extremal_interval(cm, large_sw, folded_branch_side)
    add_paths_large!(cm, INTERVAL, interval, BRANCH, folded_branch)

    # Also add branch and interval intersection with a cusp path, since the
    # cusp path at between the folded branches become longer.
    large_cusp = branch_to_cusp(cm.large_tt, cm.large_cusphandler, fold_onto_branch, folded_branch_side)
    small_cusp = large_cusp_to_small_cusp(cm, large_cusp)
    if small_cusp != 0
        add_intersection!(cm, CUSP, small_cusp, BRANCH, fold_onto_branch)
        if !is_branch_or_cusp_collapsed(cm, CUSP, small_cusp)
            click_or_interval, label, temp_storage_index = 
                large_cusp_to_position_in_click_or_interval(cm, large_cusp, LEFT)
            
            if click_or_interval == INTERVAL
                other_interval = label
            elseif click_or_interval == CLICK
                click = label
                if is_zero(cm.temp_intersections, temp_storage_index)
                    # we are at the end of a click and the beginning of the next interval
                    other_interval = click_to_interval(cm, click, RIGHT)
                    add_paths_large!(cm, INTERVAL, other_interval, TEMP, temp_storage_index)
                else
                    # we are at the middle of a click, this shouldn't happen when 
                    # the small cusp is not collapsed
                    error("The large cusp is contained in click $(click), not in an interval.")
                end
            else
                @assert false
            end

            add_intersection!(cm, CUSP, small_cusp, INTERVAL, other_interval)
        end
    end
end


"""Find the click or interval containing a cusp of the large train track.

Two things can happen:
- if a cusp of the small train track is pushed onto the large cusp,
then we there is a containing click. This happens if and only
if the cusp path corresponding to the large cusp is collapsed.
- Otherwise there is a containing interval.

"""
function large_cusp_to_position_in_click_or_interval(cm::CarryingMap, large_cusp::Int, start_side::Int)
    compute_paths_on_one_side_of_large_cusp(cm, large_cusp, start_side, 1)
    large_sw = cusp_to_switch(cm.large_cusphandler, large_cusp)

    click_or_interval, label, temp_storage_index = position_in_large_switch_to_click_or_interval(
        cm, large_sw, start_side, 1)
    return (click_or_interval, label, temp_storage_index)
end


"""
Convert the position at a switch of the large train track to
position in an interval. The position is specified by specifying the outgoing paths
at the large switch on the left or on the right of the position. These paths are stored
is a temporary storage whose index is also given as input.
"""
function position_in_large_switch_to_click_or_interval(cm::CarryingMap, 
    large_sw::Int, start_side::Int, temp_storage_index::Int)
    other_index = temp_storage_index == 2 ? 1 : 2

    for (click_or_interval, label) in accumulate_intersections_at_large_switch!(
        cm, large_sw, start_side, other_index)
        if is_smaller_or_equal(cm.temp_intersections, temp_storage_index, cm.temp_intersections, other_index)
            add_paths_large!(cm, TEMP, other_index, TEMP, temp_storage_index, -1)
            return (click_or_interval, label, other_index)
        end
    end
    @assert false
end


"""
Compute the total paths in all outgoing large branches on the specified side of a large cusp.
The result is stored in a preallocated temporary array with specified index.
"""
function compute_paths_on_one_side_of_large_cusp(cm::CarryingMap, large_cusp::Int, side::Int,
    temp_storage_index::Int)
    cm.temp_intersections[temp_storage_index, :] .= 0

    large_sw = cusp_to_switch(cm.large_tt, cm.large_cusphandler, large_cusp)
    is_flipped = large_sw < 0

    br1 = extremal_branch(cm.large_tt, large_sw, is_flipped ? otherside(side) : side)
    br2 = cusp_to_branch(cm.large_tt, cm.large_cusphandler, large_cusp, is_flipped ? side : otherside(side))
    for br in BranchIterator(cm.large_tt, br1, br2, is_flipped ? otherside(side) : side)
        add_paths_large!(cm, TEMP, temp_storage_index, BRANCH, br)
    end
end


struct IntersectionIterator
    cm::CarryingMap
    large_sw::Int
    start_side::Int
    temp_storage_index::Int
end

function Base.iterate(iter::IntersectionIterator, state::Tuple{Int,Int}=(0,0))
    click_or_interval, label = state
    if click_or_interval == 0
        # Initial state
        cm.temp_intersections[temp_storage_index, :] .= 0
        click_or_interval = INTERVAL
        label = extremal_interval(iter.cm, iter.large_sw, iter.start_side)
    end
    if click_or_interval == INTERVAL
        click = interval_to_click(iter.cm, label, otherside(side))
        if click == 0
            return nothing
        end
        add_paths_from_click!(iter.cm, click, iter.temp_storage_index)
        return ((CLICK, click), (CLICK, click))
    end
    elseif click_or_interval == CLICK
        interval = click_to_interval(iter.cm, label, otherside(side))
        add_paths_large!(iter.cm, TEMP, iter.temp_storage_index, INTERVAL, interval)
        return ((INTERVAL, interval), (INTERVAL, interval))        
    else
        @assert false
    end
end


function accumulate_intersections_at_large_switch!(
    cm::CarryingMap, large_sw::Int, start_side::Int, temp_storage_index::Int)
    IntersectionIterator(cm, large_sw, start_side, temp_storage_index)
end


function add_paths_from_small_switch!(cm::CarryingMap, sw::Int, temp_storage_index::Int)
    for br in outgoing_branches(cm.small_tt, sw)
        if !is_branch_or_cusp_collapsed(cm, BRANCH, br)
            add_intersection!(cm, BRANCH, br, TEMP, temp_storage_index)
        end
        cusp = branch_to_cusp(cm.small_cusphandler, br, RIGHT)
        if cusp != 0 || !is_branch_or_cusp_collapsed(cm, CUSP, cusp)
            add_intersection!(cm, CUSP, cusp, TEMP, temp_storage_index)
        end
    end
end


function add_paths_from_click!(cm::CarryingMap, click::Int, temp_storage_index::Int)
    sw = click_to_small_switch(cm, click)
    apply_to_switches_in_click(cm, sw, sw -> add_paths_from_small_switch!(cm, sw, temp_storage_index))
end


function is_smaller_or_equal(array1::Array{BigInt, 2}, idx1::Int, 
                            array2::Array{BigInt, 2}, idx2::Int)
    return all(array1[idx1, i] >= array1[idx2, i] for i in eachindex(size(array1)[2]))
end

function is_path_shorter_or_equal(cm::CarryingMap, branch_or_cusp1::Int, label1::Int, 
    branch_or_cusp2::Int, label2::Int)
    idx1 = branch_or_cusp_to_index(branch_or_cusp1, label1)
    idx2 = branch_or_cusp_to_index(branch_or_cusp2, label2)
    all(cm.paths[i, idx1] <= cm.paths[i, idx2] for i in eachindex(size(cm.paths)[1]))
end

function is_zero(array::Array{BigInt, 2}, idx::Int)
    return all(array[idx, i] == 0 for i in eachindex(size(array)[2]))
end

struct BranchAndCuspIterator
    tt::TrainTrack
    ch::CuspHandler
    sw::Int
end

function Base::iterate(iter::BranchAndCuspIterator, state::Tuple{Int, Int}=(0,0))
    br, branch_or_cusp = state
    if br == 0
        # initial state
        br = extremal_interval(iter.tt, iter.sw, LEFT)
        return ((BRANCH, br), (br, BRANCH))
    else
        if branch_or_cusp == BRANCH
            cusp = branch_to_cusp(iter.ch, br, RIGHT)
            if cusp != 0
                return ((CUSP, cusp), (br, CUSP)))
            else
                return nothing
            end
        else
            br = next_branch(iter.tt, br, RIGHT)
            return ((BRANCH, br), (br, BRANCH))
        end
    end
end

function outgoing_branches_and_cusps(tt::TrainTrack, ch::CuspHandler, sw::Int)
    BranchAndCuspIterator(tt, ch, sw)
end


function find_shortest_outgoing_path!(cm::CarryingMap, small_sw::Int, temp_storage_index::Int)
    for (branch_or_cusp, label) in outgoing_branches_and_cusps(cm.small_tt, cm.small_cusphandler, small_sw)
        if all(is_path_shorter_or_equal(cm, branch_or_cusp, label, branch_or_cusp2, label2) 
            for (branch_or_cusp2, label2) in outgoing_branches_and_cusps(cm.small_tt, cm.small_cusphandler, small_sw))
            return (branch_or_cusp, label)
        end
    end
    @assert false
end


function isotope_switch_as_far_as_possible(cm::CarryingMap, small_sw::Int)
    branch_or_cusp, label = find_shortest_outgoing_path!(cm, small_sw, 1)

    # If the shortest path is collapsed, there is nothing to do
    if is_branch_or_cusp_collapsed(cm, branch_or_cusp, label)
        return
    end

    # We make a copy, otherwise subtracting a path from itself would make
    # the shortest path the zero array.
    cm.temp_paths[:, 1] .= 0
    add_paths_small!(cm, TEMP, 1, branch_or_cusp, label)

    # If there is non-trivial isotopy, then we begin by breaking up click
    # at the beginning and updating the intersections.
    begin_switch_isotopy(cm, small_sw)

    # Modifying paths
    for (branch_or_cusp, label) in outgoing_branches_and_cusps(cm.small_tt, cm.small_cusphandler, small_sw)
        add_paths_small!(cm, branch_or_cusp, label, TEMP, 1, -1)
    end
    for (branch_or_cusp, label) in outgoing_branches_and_cusps(cm.small_tt, cm.small_cusphandler, -small_sw)
        add_paths_small!(cm, branch_or_cusp, label, TEMP, 1)
    end

    # Finally we merge clicks at the end of the isotopy
    end_switch_isotopy(cm, small_sw)
end


"""Update clicks, intervals and intersections when after the initial
part of a switch isotopy.

Since we move the switch from the current position, the intervals on
the left and right of it have to be joined and the trailing branches
added to the intersection. Only the trailing branches that were not
collapsed are added. It can also happen that the click does not vanish, 
but instead breaks apart to separate
clicks.
"""
function begin_switch_isotopy(cm::CarryingMap, small_sw::Int)
    large_sw = small_switch_to_large_switch(cm, small_sw)
    # is_flipped = large_sw < 0

    click = small_switch_to_click(cm, small_sw)

    # First we add intersections on the left.
    left_interval = click_to_interval(cm, click, LEFT)

    # we look backwards, so we starting from the right is the same as left,
    # when looking forward
    iter = outgoing_branches(cm.small_tt, -small_sw, RIGHT)
    collapsed_br = add_intersections_in_range!(cm, iter, left_interval, false, 1)

    if collapsed_br == 0
        # If we did not find any collapsed branches, then we remove the
        # click, delete the interval on the right and add its intersections
        # to the interval on the left.
        delete_click_and_merge!(cm, click, RIGHT)
        return
    end

    # We know that at least one click remains after the isotopy.
    # Next, we add intersections on the right.
    right_interval = next_interval(cm, left_interval, RIGHT)
    iter2 = outgoing_branches(cm.small_tt, -small_sw, LEFT)
    collapsed_br2 = add_intersections_in_range!(cm, iter2, right_interval, false, 1)

    current_collapsed_br = collapsed_br
    interval = left_interval
    while current_collapsed_br != collapsed_br2
        click, interval = insert_click!(cm, interval, RIGHT)

        end_sw = branch_endpoint(cm.small_tt, current_collapsed_br)
        set_click_to_small_switch!(cm, click, end_sw)
        apply_to_switches_in_click_after_branch!(cm, current_collapsed_br, 
            sw -> set_small_switch_to_click!(cm, sw, -click))

        # update intersections until we bump into the next collapsed branch
        iter = BranchIterator(cm.small_tt, current_collapsed_br, collapsed_br2, RIGHT)
        # we set ignore_collapsed_br_at_start to true, since we start the iteration at
        # a collapsed branch we are not interested in
        current_collapsed_br = add_intersections_in_range!(cm, iter, interval, true, 1)
    end

    # Finally, updating the switches belonging to the last click.
    # apply_to_switches_in_click_after_branch!(cm, collapsed_br2, 
        # sw -> set_small_switch_to_click!(cm, sw, -click))
end


"""
Iterate over a range of outgoing branches and cusps of the small train track and add
or subtract intersections of those branches and cusps with a specified interval. 
If a collapsed branch is found, the function is terminated and the collapsed branch is 
returned. 

- ``ignore_collapsed_br_at_start`` - if true, then the starting branch is skipped when
collapsed

"""
function add_intersections_in_range!(cm::CarryingMap, iter::BranchIterator, interval::Int,
    ignore_collapsed_br_at_start::Bool, with_sign::Int)
    start_br = iter.start_br

    for br in iter
        if start_br != br || !ignore_collapsed_br_at_start
            # If we find a collapsed branch, we break out to create a new interval
            if is_branch_or_cusp_collapsed(cm, BRANCH, br)
                return br
            end
            add_intersection!(cm, BRANCH, br, INTERVAL, interval)
        end
        cusp = branch_to_cusp(cm.small_cusphandler, branch, otherside(iter.start_side))

        if cusp != 0 && !is_branch_or_cusp_collapsed(cm, CUSP, cusp)
            add_intersection!(cm, CUSP, cusp, INTERVAL, interval)
        end
    end
    # No collapsed branches were found.
    return 0
end


function find_first_collapsed_br(cm::CarryingMap, small_sw::Int, start_side::Int)
    for br in outgoing_branches(cm.small_tt, small_sw, start_side)
        if is_branch_or_cusp_collapsed(cm, BRANCH, br)
            return br
        end
    end
    return 0
end


"""Update clicks, intervals and intersections at the final part of a
switch isotopy.

Like begin_switch_isotopy(), this involves updating
intersection numbers and creating and merging clicks.
"""
function end_switch_isotopy(cm::CarryingMap, small_sw::Int)
    # First we need to find the switch of the large train track where the
    # isotopy gets stuck.

    first_collapsed_br = find_first_collapsed_br(cm, small_sw, LEFT)
    
    if first_collapsed_br == 0
        # No branch is collapsed. Then a cusp has to be collapsed.
        collapsed_cusp = 0
        left_interval = 0
        right_interval = 0
        for br in outgoing_branches(cm.small_tt, small_sw)
            cusp = branch_to_cusp(cm.small_cusphandler, br, RIGHT)
            if cusp != 0 && is_branch_or_cusp_collapsed(cm, CUSP, cusp)
                large_cusp = small_cusp_to_large_cusp(cm, cusp)
                large_sw = cusp_to_switch(cm.large_tt, large_cusp)
                # is_flipped = large_sw < 0
                click_or_interval, label, temp_storage_index =
                    large_cusp_to_position_in_click_or_interval(cm, large_cusp, LEFT)
                # The large cusp could only be contained in a click if the small cusp
                # was pushed up on it before the isotopy. But in that case, the isotopy
                # would not be possible, so we would not be here.
                @assert click_or_interval == INTERVAL
                left_interval = label
                right_interval, new_click = insert_click!(cm, left_interval, RIGHT)
                set_small_switch_to_click!(cm, small_sw, new_click)
                set_click_to_small_switch!(cm, new_click, small_sw)
                add_paths_large!(cm, INTERVAL, right_interval, TEMP, temp_storage_index)
                add_paths_large!(cm, INTERVAL, left_interval, TEMP, temp_storage_index, -1)
                collapsed_cusp = cusp
                break
            end
        end
        @assert collapsed_cusp != 0

        # It is possible that there are multiple cusp paths that are collapsed.
        # In that case, creating more intervals is not necessary, but we need to 
        # remove some intersections with the surrounding intervals.

        current_interval = left_interval
        for (branch_or_cusp, label) in outgoing_branches_and_cusps(cm.small_tt, cm.small_cusphandler, small_sw)
            if branch_or_cusp == CUSP || label == collapsed_cusp
                current_interval = right_interval
            else
                if !is_branch_or_cusp_collapsed(cm, branch_or_cusp, label)
                    add_intersection!(cm, branch_or_cusp, label, INTERVAL, current_interval, -1)
                end
            end
        end
    else
        # There is at least one collapsed branch.

        # Finding the interval left of the first collapsed branch.
        left_end_sw = branch_endpoint(cm.small_tt, first_collapsed_br)
        left_click = small_switch_to_click(cm, -left_end_sw)
        left_interval = click_to_interval(cm, left_click, LEFT)

        # subtracting intersections from the interval left of the first collapsed branch.
        iter = outgoing_branches(cm.small_tt, small_sw, LEFT)
        left_collapsed_br = add_intersections_in_range!(cm, iter, left_interval, false, -1)
        @assert left_collapsed_br == first_collapsed_br

        # Finding the last collapsed branch and the interval to the right of it.
        right_collapsed_br = find_first_collapsed_br(cm, small_sw, RIGHT)
        right_end_sw = branch_endpoint(cm.small_tt, right_collapsed_br)
        right_click = small_switch_to_click(cm, -right_end_sw)
        right_interval = click_to_interval(cm, click, RIGHT)

        # subtracting intersections from the interval right of the last collapsed branch.
        iter = outgoing_branches(cm.small_tt, small_sw, RIGHT)
        last_collapsed_br = add_intersections_in_range!(cm, iter, right_interval, false, -1)
        @assert last_collapsed_br == right_collapsed_br

        # deleting clicks in the middle
        br = last_collapsed_br
        while br != first_collapsed_br
            if is_branch_or_cusp_collapsed(cm, BRANCH, br)
                end_sw = branch_endpoint(cm.small_tt, br)
                current_click = small_switch_to_click(cm, -end_sw)
                apply_to_switches_in_click_after_branch!(cm, br, sw -> set_small_switch_to_click(cm, sw, left_click))
                delete_click_and_merge!(cm, current_click, LEFT)
            end
            br = next_branch(cm.small_tt, br, LEFT)
        end
    end
end