--[[
    Q * U * E * N * C * E  x  molly_the_poly

    a probababilistic
    4-track MIDI sequencer
    for norns and grid

    Rob Schoen
    millxing at gmail

    inspired by Turing Machine, Fugue Machine, and Physical (Norns Study #4)

    random tips:
        bottom row is always the toolbar -
            pause, mutes for tracks 1-4, lock all, clear all, select tracks 1-4,
            and select settings page
        hold encoder 3 to see the midi notes in the sequence for the current track
        on the settings page, the eight buttons in rows 5-6, cols 13-16 are currently
            unassigned, but for now you can hit any of them to resync all the sequences

    updated for norns 2.0 + molly_the_poly output by _ground_state_ (https://llllllll.co/u/ground_state/summary)
]]
engine.name = 'MollyThePoly'
local music = require 'musicutil'
local beatclock = require 'beatclock'
local MollyThePoly = require 'molly_the_poly/lib/molly_the_poly_engine'
local options = {}
options.OUTPUT = {'audio'}

-- connect grid
local grid_device = grid.connect()

-- midi code
--[[
local midi_device = midi.connect()
midi_device.event = function(data)
    local d = midi.to_msg(data)
    if d.type == 'note_on' then
        transpose = d.note - 60
    end
end
--]]

-- declare variables
local position = {}
local tempomod = {}
local seqlen = {}
local dispersion = {}
local press = 0
local transpose = 0
local page = 0
local tpage = 0
local pagecopy = 0
local lock = 0
local pause = 0
local tick = 0
local tonicnum = 0
local toniclist = {}
local changelist = {}
local rflist = {}
local change = {}
local restfreq = {}
local mnote = {}
local mute = {}
local maxscreen = 0
local maxgrid = 0
local inact = 0
local mode = 0
local center = 0
local scale = {}
local tempo = 0
local steps = {}
local rests = {}
local steps_copy = {}
local rests_copy = {}
local clk = beatclock.new()


function init()
    opening_animation()
    math.randomseed(os.time())

    -- initalize variables
    for track = 1, 4 do
        position[track] = 16
        tempomod[track] = 1
        seqlen[track] = 16
        dispersion[track] = 5
    end
    page = 1
    tpage = -99
    pagecopy = 1
    pause = 1
    toniclist = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}
    tonicnum = 1

    -- probabilities for randomness and rest frequencies
    changelist = {
        0,
        (1 / 6) ^ 1.5,
        (2 / 6) ^ 1.5,
        (3 / 6) ^ 1.5,
        (4 / 6) ^ 1.5,
        (5 / 6) ^ 1.5,
        1.00,
    }
    rflist = {
        0,
        (1 / 6) ^ 1.5,
        (2 / 6) ^ 1.5,
        (3 / 6) ^ 1.5,
        (4 / 6) ^ 1.5,
        (5 / 6) ^ 1.5,
        1,
    }

    -- set defaults
    change = {7, 1, 1, 1}
    restfreq = {1, 1, 1, 1}
    mnote = {0, 0, 0, 0}
    mute = {0, 0, 0, 0}

    -- norns and grid parameters
    maxscreen = 6
    maxgrid = 10
    inact = 4

    -- set up musical scale
    mode = 12 -- default = major pentatonic
    center = 48 + (tonicnum - 1) -- tonic center
    scale = music.generate_scale_of_length(center - 12, music.SCALES[mode].name, 24)
    tempo = 60 -- default tempo

    -- initalize sequences
    for track = 1, 4 do
        steps[track] = {}
        rests[track] = {}
        for step = 1, seqlen[track] do
            steps[track][step] = 15
            rests[track][step] = 1
            steps_copy[step] = steps[1][step]
            rests_copy[step] = rests[1][step]
        end
    end

    --[[
    params:add {
        type = "number",
        id = "midi_out_device",
        name = "midi out device",
        min = 1,
        max = 4,
        default = 1,
        action = function(value)
            midi_out_device = midi.connect(value)
        end
    }
    --]]

    --[[
    params:add {
       type = "number",
       id = "midi_out_channel",
       name = "midi out channel",
       min = 1,
       max = 16,
       default = 1,
       action = function(value)
           midi_out_channel = value
       end
    }
    --]]

    -- clock settings
    --[[
    clk_midi = midi.connect()
    clk_midi.event = clk.process_midi
    --]]
    clk.on_step = count
    --[[
    clk.on_select_internal = function()
        clk:start()
    end
    clk.on_select_external = function()
        print('external')
    end
    --]]
    params:add{
        type = 'option',
        id = 'output',
        name = 'output',
        options = options.OUTPUT,
        action = function()
        end,
    }
    clk:add_clock_params()
    params:set('bpm', tempo)
    params:add_separator()
    MollyThePoly.add_params()
    redraw()
    grid_redraw()
    params:default()
end


-- redraw screen
function redraw()
    screen.clear()
    screen.level(maxscreen)
    screen.move(0, 10)
    screen.text('global bpm : ' .. params:get('bpm'))
    screen.move(0, 20)
    screen.text('tonic and scale : ' .. toniclist[tonicnum] .. ' ' .. music.SCALES[mode]
                    .name)
    screen.move(0, 30)
    screen.text('sequence lengths : ' .. seqlen[1] .. ' ' .. seqlen[2] .. ' ' .. seqlen[3]
                    .. ' ' .. seqlen[4])
    screen.move(0, 40)
    screen.text('tempo modifiers : ' .. tempomod[1] .. ' ' .. tempomod[2] .. ' '
                    .. tempomod[3] .. ' ' .. tempomod[4])
    screen.move(0, 50)
    screen.text('dispersions : ' .. dispersion[1] .. ' ' .. dispersion[2] .. ' '
                    .. dispersion[3] .. ' ' .. dispersion[4])
    screen.update()
end


-- redraw grid
function grid_redraw()
    if tpage ~= page then
        grid_device:all(0)
        grid_redraw_ctrl()
    end
    if page == 0 and tpage ~= page then
        grid_redraw_home()
    end
    if page > 0 then
        grid_redraw_page()
    end
    grid_device:refresh()
    tpage = page
end


-- redraw toolbar at bottom row of grid
function grid_redraw_ctrl()
    grid_device:led(1, 8, pause == 1 and maxgrid or inact) -- pause
    for button = 3, 6 do
        grid_device:led(button, 8, mute[button - 2] == 1 and maxgrid or inact) -- mutes(1-4)
    end
    grid_device:led(8, 8, lock == 1 and maxgrid or inact) -- lock all
    grid_device:led(9, 8, inact) -- randomize all
    for button = 11, 14 do
        grid_device:led(button, 8, (page == (button - 10)) and maxgrid or inact) -- select track pages (1-4)
    end
    grid_device:led(16, 8, page == 0 and maxgrid or inact) -- select home page
end


-- redraw home page of grid
function grid_redraw_home()
    grid_device:led(1, 2, inact)
    grid_device:led(1, 3, inact) -- seqlen 1
    grid_device:led(2, 2, inact)
    grid_device:led(2, 3, inact) -- seqlen 2
    grid_device:led(3, 2, inact)
    grid_device:led(3, 3, inact) -- seqlen 3
    grid_device:led(4, 2, inact)
    grid_device:led(4, 3, inact) -- seqlen 4
    grid_device:led(6, 2, inact)
    grid_device:led(6, 3, inact) -- bpm coarse
    grid_device:led(7, 2, inact)
    grid_device:led(7, 3, inact) -- bpm fi
    grid_device:led(10, 2, inact)
    grid_device:led(10, 3, inact) -- tonic
    grid_device:led(11, 2, inact)
    grid_device:led(11, 3, inact) -- scale
    grid_device:led(13, 2, inact)
    grid_device:led(13, 3, inact) -- tempo mod 1
    grid_device:led(14, 2, inact)
    grid_device:led(14, 3, inact) -- tempo mod 2
    grid_device:led(15, 2, inact)
    grid_device:led(15, 3, inact) -- tempo mod 3
    grid_device:led(16, 2, inact)
    grid_device:led(16, 3, inact) -- tempo mod 4
    grid_device:led(1, 5, inact)
    grid_device:led(1, 6, inact) -- dispersion 1
    grid_device:led(2, 5, inact)
    grid_device:led(2, 6, inact) -- dispersion 2
    grid_device:led(3, 5, inact)
    grid_device:led(3, 6, inact) -- dispersiom 3
    grid_device:led(4, 5, inact)
    grid_device:led(4, 6, inact) -- dispersion 4
    grid_device:led(13, 5, inact)
    grid_device:led(13, 6, inact) -- unassigned
    grid_device:led(14, 5, inact)
    grid_device:led(14, 6, inact) -- unassigned
    grid_device:led(15, 5, inact)
    grid_device:led(15, 6, inact) -- unassigned
    grid_device:led(16, 5, inact)
    grid_device:led(16, 6, inact) -- unassigned
end


-- redraw the track view for the selected track
function grid_redraw_page()
    -- turn off all leds on the top 2 rows
    for led = 1, seqlen[page] do
        grid_device:led(led, 1, 0)
        grid_device:led(led, 2, 0)
    end

    -- draw top 2 rows (sequence position and scale degrees)
    for led = 1, seqlen[page] do
        grid_device:led(led, 1, led == position[page] and maxgrid or inact)
        if rests[page][led] == 0 and steps[page][led] > 0 then
            local val = math.floor((steps[page][led] / #scale) * maxgrid) + 1
            if val > maxgrid then
                val = maxgrid
            end
            if val < 0 then
                val = 1
            end
            grid_device:led(led, 2, val)
        else
            grid_device:led(led, 2, 0)
        end
    end

    -- draw randomness selector and rest frequency selector on row 4
    for led = 1, 7 do
        grid_device:led(led, 4, led == change[page] and maxgrid or inact)
        grid_device:led(led + 9, 4, led == restfreq[page] and maxgrid or inact)
    end

    -- draw various buttons on rows 6 and 7
    grid_device:led(1, 6, (press == 106) and maxgrid or inact) -- copy
    grid_device:led(2, 6, (press == 206) and maxgrid or inact) -- paste
    grid_device:led(4, 6, (press == 406) and maxgrid or inact) -- shift ->
    grid_device:led(5, 6, (press == 506) and maxgrid or inact) -- shift <-
    grid_device:led(12, 6, (press == 1206) and maxgrid or inact) -- transpose up
    grid_device:led(13, 6, (press == 1306) and maxgrid or inact) -- transpose down
    grid_device:led(15, 6, (press == 1506) and maxgrid or inact) -- invert
    grid_device:led(16, 6, (press == 1606) and maxgrid or inact) -- reverse
    grid_device:led(8, 7, (press == 807) and maxgrid or inact) -- track lock
    grid_device:led(9, 7, (press == 907) and maxgrid or inact) -- track clear
end


-- grid events
function grid_device.key(x, y, z)
    local coord = x * 100 + y -- integer code for coordinates of grid event

    -- settings page button press events ---------------------------------------------------
    if z == 1 and page == 0 then
        press = 0
        -- coarse global tempo up
        if coord == 602 then
            tempo = tempo + 10
            params:set('bpm', tempo)
            press = coord
        end

        -- coarse global tempo down
        if coord == 603 then
            tempo = tempo - 10
            if tempo < 1 then
                tempo = 10
            end
            params:set('bpm', tempo)
            press = coord
        end

        -- fine global tempo up
        if coord == 702 then
            tempo = tempo + 1
            params:set('bpm', tempo)
            press = coord
        end

        -- fine global tempo down
        if coord == 703 then
            tempo = tempo - 1
            if tempo < 1 then
                tempo = 1
            end
            params:set('bpm', tempo)
            press = coord
        end

        -- tonic up
        if coord == 1002 then
            tonicnum = tonicnum + 1
            if tonicnum > 12 then
                tonicnum = 1
            end
            center = 48 + (tonicnum - 1) -- tonic center
            scale = music.generate_scale_of_length(center - 12, music.SCALES[mode].name, 24)
            press = coord
        end

        -- tonic down
        if coord == 1003 then
            tonicnum = tonicnum - 1
            if tonicnum < 1 then
                tonicnum = 12
            end
            center = 48 + (tonicnum - 1) -- tonic center
            scale = music.generate_scale_of_length(center - 12, music.SCALES[mode].name, 24)
            press = coord
        end

        -- scale up
        if coord == 1102 then
            mode = mode + 1
            if mode > 47 then
                mode = 1
            end
            center = 48 + (tonicnum - 1) -- tonic center
            scale = music.generate_scale_of_length(center - 12, music.SCALES[mode].name, 24)
            press = coord
        end

        -- scale down
        if coord == 1103 then
            mode = mode - 1
            if mode < 1 then
                mode = 47
            end
            center = 48 + (tonicnum - 1) -- tonic center
            scale = music.generate_scale_of_length(center - 12, music.SCALES[mode].name, 24)
            press = coord
        end

        -- sequence lengths for tracks 1-4
        if x > 0 and x < 5 and (y == 2 or y == 3) then
            local local_x = x
            if y == 2 then
                seqlen[local_x] = seqlen[local_x] + 1
                if seqlen[local_x] > 16 then
                    seqlen[local_x] = 16
                end
            else
                seqlen[local_x] = seqlen[local_x] - 1
                if seqlen[local_x] < 1 then
                    seqlen[local_x] = 16
                end
            end
            position[local_x] = 16
            press = coord
        end

        -- dispersion parameter for tracks 1-4
        if x > 0 and x < 5 and (y == 5 or y == 6) then
            local local_x = x
            if y == 5 then
                dispersion[local_x] = dispersion[local_x] + 1
                if dispersion[local_x] > 10 then
                    dispersion[local_x] = 10
                end
            else
                dispersion[local_x] = dispersion[local_x] - 1
                if dispersion[local_x] < 0 then
                    dispersion[local_x] = 0
                end
            end
            press = coord
        end

        -- tempo modifier for tracks 1-4
        if x > 12 and (y == 2 or y == 3) then
            local x_offset = x - 12
            if y == 2 then
                tempomod[x_offset] = tempomod[x_offset] + 1
                if tempomod[x_offset] > 8 then
                    tempomod[x_offset] = 8
                end
            else
                tempomod[x_offset] = tempomod[x_offset] - 1
                if tempomod[x_offset] < 1 then
                    tempomod[x_offset] = 1
                end
            end
            press = coord
        end

        -- re-sync all sequences
        if x > 12 and (y == 5 or y == 6) then
            sync_tracks()
            press = coord
        end
    end

    -- track page button press events ---------------------------------------------------
    if z == 1 and page > 0 then

        -- change probability (row 4, left side)
        if y == 4 and x < 8 then
            change[page] = x
        end

        -- rest frequency (row 4, right side)
        if y == 4 and x > 9 then
            restfreq[page] = x - 9
        end

        -- sequence position (top row)
        if y == 1 then
            position[page] = x
        end

        -- toggle rest (2nd row from top)
        if y == 2 then
            rests[page][x] = 1 - rests[page][x]
        end

        -- copy sequence (row 6, col 1)
        if y == 6 and x == 1 then
            for step = 1, 16 do
                steps_copy[step] = steps[page][step]
                rests_copy[step] = rests[page][step]
            end
            pagecopy = page
            press = coord
        end

        -- paste sequence (row 6, col 2)
        if y == 6 and x == 2 then
            for step = 1, 16 do
                steps[page][step] = steps_copy[step]
                rests[page][step] = rests_copy[step]
            end
            seqlen[page] = seqlen[pagecopy]
            change[page] = 1
            press = coord
        end

        -- shift left (row 6, col 4)
        if coord == 406 then
            shift_left()
            press = coord
        end

        -- shift right (row 6, col 5)
        if coord == 506 then
            shift_right()
            press = coord
        end

        -- scalar transpose down (row 6, col 12)
        if coord == 1206 then
            for step = 1, seqlen[page] do
                steps[page][step] = steps[page][step] - 1
                if steps[page][step] < 1 then
                    steps[page][step] = #scale
                end
            end
            press = coord
        end

        -- scalar transpose up (row 6 col 13)
        if coord == 1306 then
            for step = 1, seqlen[page] do
                steps[page][step] = steps[page][step] + 1
                if steps[page][step] > #scale then
                    steps[page][step] = 1
                end
            end
            press = coord
        end

        -- invert (row 6 col 15)
        if coord == 1506 then
            for step = 1, seqlen[page] do
                steps[page][step] = (12 - steps[page][step]) + 12
            end
            press = coord
        end

        -- reverse (row 6 col 16)
        if coord == 1606 then
            local temp_steps = deepcopy(steps[page])
            local temp_rests = deepcopy(rests[page])
            for step = 1, seqlen[page] do
                steps[page][step] = temp_steps[seqlen[page] + 1 - step]
                rests[page][step] = temp_rests[seqlen[page] + 1 - step]
            end
            press = coord
        end

        -- lock track (row 7 col 8  -- sets randomness for track to 0)
        if coord == 807 then
            change[page] = 1
            press = coord
        end

        --  clear track (row 7 col 9)
        if coord == 907 then
            change[page] = 1
            restfreq[page] = 1
            for step = 1, 16 do
                steps[page][step] = 15
                rests[page][step] = 1
            end
            press = coord
        end
    end

    -- toolbar button press events ---------------------------------------------------
    if z == 1 and y == 8 then

        -- pause all sequences (row 8, col 1)
        if coord == 108 then
            pause = 1 - pause
            if pause == 0 then
                clk:start()
            else
                clk:stop()
            end

            -- clear all note ons
            if pause == 1 then
                --[[
                for track = 1, 4 do
                    if mnote[track] > 0 then
                        midi_device.note_off(mnote[track], 0, p)
                    end
                end
                --]]
                engine.noteKillAll()
            end
        end

        -- mute tracks (row 8 cols 3-6)
        if y == 8 and (x >= 3 and x <= 6) then
            mute[x - 2] = 1 - mute[x - 2]
        end

        -- lock all tracks (row 8 col 8)
        if y == 8 and x == 8 then
            lock = 1 - lock
            for track = 1, 4 do
                change[track] = 1
            end
            grid_device:led(x, y, maxgrid)
            grid_device:refresh()
        end

        -- clear all tracks (row 8 col 9)
        if y == 8 and x == 9 then
            for track = 1, 4 do
                change[track] = 1
                restfreq[track] = 1
                for step = 1, seqlen[track] do
                    steps[track][step] = 15
                    rests[track][step] = 1
                end
            end
            press = coord
        end

        -- select track page (row 8 cols 11-14)
        if y == 8 and (x >= 11 and x <= 14) then
            page = x - 10
        end

        -- select settings page (row 8 col 16)
        if y == 8 and x == 16 then
            page = 0
        end

        -- light up a pressed button
        if press > 0 then
            grid_device:led(x, y, maxgrid)
            grid_device:refresh()
        end
    end

    -- button unpressed events
    if z == 0 then
        if press > 0 then
            grid_device:led(x, y, inact)
            press = 0
        else
            grid_device:led(x, y, 0)
            grid_device:refresh()
        end
    end

    -- pause led
    if pause == 1 then
        grid_device:led(1, 8, maxgrid)
    else
        grid_device:led(1, 8, inact)
    end

    -- mute leds
    for track = 1, 4 do
        if mute[track] == 1 then
            grid_device:led(2 + track, 8, maxgrid)
        else
            grid_device:led(2 + track, 8, inact)
        end
    end

    -- track select leds
    for track = 1, 4 do
        if page == track then
            grid_device:led(10 + track, 8, maxgrid)
        else
            grid_device:led(10 + track, 8, inact)
        end
    end

    -- settings page led
    if page == 0 then
        grid_device:led(16, 8, maxgrid)
    else
        grid_device:led(16, 8, inact)
    end

    -- turn off lock led if any track is unlocked
    for track = 1, 4 do
        if change[track] > 1 then
            lock = 0
        end
    end
    if lock == 1 then
        grid_device:led(8, 8, maxgrid)
    else
        grid_device:led(8, 8, inact)
    end

    -- redraw
    redraw()
    grid_redraw()
end


function count()
    tick = tick + 1

    -- moves the sequence ahead by one step and turns on/off notes
    for track = 1, 4 do

        -- advance the sequence position, depending on the tempo modifier
        if tick % tempomod[track] == 0 then
            position[track] = (position[track] % seqlen[track]) + 1

            -- update the sequence
            update_sequence(track)

            -- turn off the last note
            if mnote[track] > 0 or mute[track] == 1 then
                -- midi_device.note_off(mnote[track], 0, track)
                engine.noteOff(track)
            end
            local note = scale[steps[track][position[track]]]

            -- turn on a note unless there is a rest
            if rests[track][position[track]] == 0 and note ~= nil then
                note = note + transpose
                if note > 0 and mute[track] == 0 then
                    local freq = music.note_num_to_freq(note)
                    -- midi_device.note_on(note, 90, track)
                    engine.noteOn(track, freq, 90)
                    mnote[track] = note
                end
            end
        end
    end
    grid_redraw()
end


function update_sequence(track)
    -- updates each sequence in a probabilistic manner
    -- the dispersion parameter controls how big of a jump the sequence can make
    local chg = changelist[change[track]]
    local rfq = rflist[restfreq[track]]
    if (math.random() < chg) then
        local tposition = position[track] - 1
        if tposition < 1 then
            tposition = seqlen[track]
        end
        local delta = round(box_muller() * (dispersion[track] / 5))
        delta = delta + round((15 - steps[track][position[track]]) * .05)
        steps[track][position[track]] = steps[track][tposition] + delta
        if steps[track][position[track]] > #scale then
            steps[track][position[track]] = #scale - (steps[track][position[track]] - #scale)
        end
        if steps[track][position[track]] < 1 then
            steps[track][position[track]] = 1 - (steps[track][position[track]])
        end
        if (math.random() < rfq) then
            rests[track][position[track]] = 1
        else
            rests[track][position[track]] = 0
        end
    end
end


function key(n, z)
    -- while held, button 3 displays the midi notes of the sequence on the selected track
    if n == 3 and z == 1 then
        screen.clear()
        local bb = ' '
        for step = 1, seqlen[page] do
            local aa = scale[steps[page][step]]
            if rests[page][step] == 1 then
                aa = 0
            end
            if aa < 100 then
                if aa == 0 then
                    aa = ('  ' .. aa)
                else
                    aa = (' ' .. aa)
                end
            end
            bb = (bb .. aa .. ' ')
        end
        screen.move(0, 10)
        screen.text('Track #' .. page)
        for track = 1, 4 do
            screen.move(0, 20 + 10 * track)
            local cc = string.sub(bb, (track - 1) * 16 + 1, (track - 1) * 16 + 16)
            screen.text(cc)
        end
        screen.update()
    end
    if n == 3 and z == 0 then
        redraw()
    end
end


function shift_left()
    -- shifts the sequence to the left, wrapping the first note to the end of the sequence
    -- rewrite this using deepcopy
    local stp = steps[page][1]
    local rst = rests[page][1]
    for step = 1, (seqlen[page] - 1) do
        steps[page][step] = steps[page][step + 1]
        rests[page][step] = rests[page][step + 1]
    end
    steps[page][seqlen[page]] = stp
    rests[page][seqlen[page]] = rst
end


function shift_right()
    -- shifts the sequence to the right, wrapping the last note to the start of the sequence
    -- rewrite this using deepcopy
    local stp = steps[page][seqlen[page]]
    local rst = rests[page][seqlen[page]]
    for step = seqlen[page], 2, -1 do
        steps[page][step] = steps[page][step - 1]
        rests[page][step] = rests[page][step - 1]
    end
    steps[page][1] = stp
    rests[page][1] = rst
end


function deepcopy(orig)
    -- make a copy of a table instead of making a direct reference
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


function reverse(orig)
    -- reverse a numeric table
    local i, j = 1, #orig
    while i < j do
        orig[i], orig[j] = orig[j], orig[i]
        i = i + 1
        j = j - 1
    end
end


function sync_tracks()
    for track = 1, 4 do
        position[track] = 0
    end
end


-- box_muller simulates normally distributed random numbers from uniform random numbers
function box_muller()
    return math.sqrt(-2 * math.log(math.random())) * math.cos(2 * math.pi * math.random())
end


-- round to nearest integer
function round(num)
    local under = math.floor(num)
    local upper = math.floor(num) + 1
    local underV = -(under - num)
    local upperV = upper - num
    if (upperV > underV) then
        return under
    else
        return upper
    end
end


-- gratuitous opening animation
function opening_animation()
    for a = 8, 1, -1 do
        grid_device:all(0)
        for i = 1, 8 do
            for j = 1 + (a - 1), 16 - (a - 1) do
                grid_device:led(j, i, math.random(0, 15))
            end
        end
        grid_device:refresh()
        sleep(0.1)
    end
    for a = 1, 8 do
        grid_device:all(0)
        for i = 1, 8 do
            for j = 1 + (a - 1), 16 - (a - 1) do
                grid_device:led(j, i, math.random(0, 15))
            end
        end
        grid_device:refresh()
        sleep(0.1)
    end
    grid_device:all(0)
    grid_device:refresh()
end


-- pause lua code
function sleep(secs)
    local ntime = os.clock() + secs
    repeat
    until os.clock() > ntime
end
