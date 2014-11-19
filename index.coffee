MAX_CANVAS_WIDTH = 32767
ONE_ON_ROOT_TWO = 1/Math.sqrt(2)

# Drag and drop helper. Calls the callback whenever the element has 
# something dropped onto it, and adds a class 'dragover' to the element
# when something is being dragged over the top of it

on_drop = (element, callback) ->
    
    $element = $(element)
    counter = 0

    update_counter = (num) ->
        counter = num
        if counter > 0
            $element.addClass('dragover')
        else
            $element.removeClass('dragover')

    $element.on 'dragenter', (event) ->
        update_counter counter + 1
        $element.addClass('dragover')

    $element.on 'dragleave', (event) ->
        update_counter counter - 1

    $element.on 'dragover', (event) ->
        event.preventDefault()

    $element.on 'dragend', (event) ->
        update_counter 0

    $element.on 'drop', (event) ->
        event.preventDefault()
        update_counter 0
        callback.apply this, arguments

# Promise-ish functions

# Run a function next tick cycle

tick = (func) -> setTimeout func, 0

# Utility function for promises

call_listener = (listener, args) -> tick ->

    listener.apply {
        callback: -> listener.promise.do.apply this, arguments
    }, args

# Creates a promise

promise = ->

    done = false
    listeners = []
    args = []
    
    return {

        then: (listener) ->

            listener.promise = promise()

            if done
                call_listener listener, args
            else
                listeners.push listener

            return listener.promise

        then_do: (listener) ->

            @then ->
                listener.apply this, arguments
                @callback.apply this, arguments

        do: ->

            args = arguments

            for listener in listeners
                call_listener listener, args

            done = true
            listeners = []

            return this

        clear: ->
            listeners = []
            return this
    }

# Creates a promise which will fire immediately

begin = -> promise().do()

# Audio loading helper. Takes in an audio file, and calls back with the 
# raw signal in the form of a Float32Array

get_channel_data = (file, callback) ->
    
    reader = new FileReader()
    reader.readAsArrayBuffer(file)
    console.log 'loading file', file
    reader.onloadend = ->
        console.log 'decoding file', file
        window.audio_context.decodeAudioData reader.result, (buffer) ->
            console.log 'done', buffer
            callback buffer.getChannelData(0), buffer

# Signal processing functions

# Convolve a signal with an FIR function.  'range' adjusts the size of
# the response.  The default is quite low.  

convolve = (data, func, range = 8) ->
    
    response = for a in [-range...range]
        func(a) ? 0
    
    convolution = new Float32Array(data.length) # Initialises to 0
    
    for signal, signal_index in data

        continue if signal_index - range < 0
        continue if signal_index + range >= data.length

        for filter, filter_index in response
            convolution[signal_index] += data[signal_index + filter_index - range] * filter

    return convolution

# Combines two signals together using the given function

combine = (data1, data2, func) ->

    result = new Float32Array(data1.length)

    for d, index in data1
        result[index] = func d, data2[index]

    return result

# Applies a given function on the signal, returning the new result

map = (data, func) ->
    
    result = new Float32Array(data.length)

    for d, i in data
        result[i] = func d, i

    return result

# Re-represents the same signal with less samples

downsample = (data, ratio = 2) ->
    
    # TODO: Remove problematic frequencies from the signal

    result = new Float32Array(data.length/ratio)

    for a in [0...result.length]
        result[a] = data[Math.floor a*ratio]

    return result

find_best_harmonic = (data, echoes, min, max) ->
    
    best = [min..max].reduce (max, index) ->

        sum = 0

        for a in [1..echoes]
            sum += data[Math.floor index*a/echoes]

        sum /= echoes

        if max.score >= sum
            return max
        else
            return {
                position: index
                score: sum
                echoes: echoes
            }

    , position: 0, score: 0, echoes: 0

    best.likelihood = data[best.position] + Math.max data[best.position*2-1], data[best.position*2], data[best.position*2+1]

    return best

# Some common lambdas used in the above functions

hilbert_transform = (x) -> if x % 2 == 0 then 0 else 1/(Math.PI*x)
modulus = (a, b) -> Math.sqrt a*a + b*b
argument = (a, b) -> Math.atan2 b, a
real_part = (a, b) -> a * Math.cos b
imag_part = (a, b) -> a * Math.sin b

# Drawing functions

# Ensures that only one drawing operation is occurring at a time (because for some reason contexts are shared...)

draw_queue = begin()

# Clear all canvases on the page, and clears any queued renders

clear_canvases = -> draw_queue.clear().then_do ->

    for canvas in $('canvas')
        canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height)

# Used by the higher level drawing functions below

draw_line = (data, context, scale, detail, callback) ->

    chunk = 128
    index = 0

    interval = setInterval ->

        context.beginPath()
        context.moveTo (index-1)/detail, (data[index-1] ? 0) * scale

        for a in [index .. Math.floor index + detail * chunk]
            context.lineTo a/detail, data[a] * scale

        context.stroke()

        index += Math.floor detail * chunk

        if index >= data.length or index/detail > MAX_CANVAS_WIDTH
            clearInterval interval
            context.restore()
            callback?()

    , 0

# Draw a waveform (top canvas)

draw_waveform = (data, { colour, detail, scale, adjust }) -> draw_queue = draw_queue.then ->

    colour ?= '#000'
    detail ?= 0.5
    scale ?= 256
    adjust ?= true

    canvas = $('#waveform canvas')[0]

    if adjust
        canvas_width = Math.min MAX_CANVAS_WIDTH, Math.floor(data.length/detail)
        canvas.width = canvas_width if canvas.width != canvas_width

    context = canvas.getContext '2d'
    context.save()
    context.translate 0, 256
    context.scale 1, -1
    context.strokeStyle = colour

    draw_line data, context, scale, detail, @callback

# Draw a frequency function (bottom canvas)

draw_frequencies = (data, { colour, detail, scale }) -> draw_queue = draw_queue.then ->

    colour ?= '#000'
    detail ?= 1
    scale ?= 16

    canvas = $('#frequencies canvas')[0]
    canvas_width = Math.min MAX_CANVAS_WIDTH, Math.floor(data.length/detail)
    canvas.width = canvas_width if canvas.width != canvas_width

    context = canvas.getContext '2d'
    context.save()
    context.translate 0, 512
    context.scale 1, -1
    context.strokeStyle = colour

    draw_line data, context, scale, detail, @callback

# Perform a Fast Fourier Transform on an imaginary signal 'data'

fft = (data, from, count) ->
    
    half_count = count/2

    # Pre-compute the twiddle values for the recursion

    cache_real = new Float32Array(half_count)
    cache_imag = new Float32Array(half_count)

    for k in [0...half_count]
        angle = -2 * Math.PI * k/count
        cache_real[k] = Math.cos(angle)
        cache_imag[k] = Math.sin(angle)

    # Perform the transform recursively

    return fft_recurse data, from, count, 1, cache_real, cache_imag

# The recursive portion of the Fast Fourier Transform algorithm

fft_recurse = (data, from, count, step = 1, cache_real, cache_imag) ->

    # Check for the base case
    # TODO: Investigate placing the base case at a higher count than 1

    if count == 1
        return [ new Float32Array([ data[0][from] ]), new Float32Array([ data[1][from] ]) ]

    half_count = count/2

    # Recurse

    [ first_half_real, first_half_imag ] = fft_recurse(data, from, half_count, step*2, cache_real, cache_imag)
    [ second_half_real, second_half_imag ] = fft_recurse(data, from + step, half_count, step*2, cache_real, cache_imag)

    # Combine the two results together using the twiddle factors

    result_real = new Float32Array(count)
    result_imag = new Float32Array(count)

    for k in [0...half_count]

        # Fetch the twiddle factor from the pre-computed values

        real = cache_real[k*step]
        imag = cache_imag[k*step]

        # Multiply the twiddle factor with the odd transform

        rr = real * second_half_real[k]
        ri = real * second_half_imag[k]
        ir = imag * second_half_real[k]
        ii = imag * second_half_imag[k]

        # Add the result to the even transform

        result_real[k] = (first_half_real[k] + rr - ii) * ONE_ON_ROOT_TWO
        result_imag[k] = (first_half_imag[k] + ri + ir) * ONE_ON_ROOT_TWO

        # Use a shortcut to easily calculate the second half of the results

        result_real[k+half_count] = (first_half_real[k] - (rr - ii)) * ONE_ON_ROOT_TWO
        result_imag[k+half_count] = (first_half_imag[k] - (ri + ir)) * ONE_ON_ROOT_TWO

    return [ result_real, result_imag ]

# Take a real representation of a signal and return its imaginary representation

imaginary = (data) -> [ data, new Float32Array(data.length) ]

# Time how long a function takes to execute

time = (message, func) ->
    console.log "Starting #{message}"
    begin = Date.now()
    func()
    console.log "#{message} took #{Date.now() - begin}"

# A basic test

test = ->

    # test = ( (if a == 0 then 1 else Math.sin(2*Math.PI*a/8)/(2*Math.PI*a/8)) for a in [-512*1024...512*1024] )
    # test = ( (if a == 0 then 1 else Math.sin(2*Math.PI*a/8)/(2*Math.PI*a/8)) for a in [-512...512] )
    # test = [ 0, 1, 0, -1, 0, 1, 0, -1 ]
    test = ( Math.sin(2*Math.PI*a/128) * Math.sin(2*Math.PI*a/4) for a in [-512...512] ) 

    transform_size = test.length
    sample_rate = 512
    downsample_ratio = 1
    draw_detail = 0.5

    draw_waveform test, colour: 'rgba(0, 0, 0, 0.5)', detail: draw_detail

    [ convolution, envelope, test_real, test_imag, test_freq, transform_real, transform_imag, frequencies, phases ] = []

    begin().then_do ->
        time 'convolving...', ->
            convolution = convolve test, hilbert_transform

    .then_do ->
        time 'enveloping...', ->
            envelope = combine test, convolution, modulus

    .then_do ->
        draw_waveform envelope, colour: 'rgba(0, 0, 255, 0.5', detail: draw_detail
    
    .then_do ->
        console.log 'transforming...'
        [ transform_real, transform_imag ] = fft(imaginary(envelope), 0, transform_size)

    .then_do ->
        console.log 'absoluting...'
        frequencies = combine transform_real, transform_imag, modulus
        phases = combine transform_real, transform_imag, argument
        phases = map phases, (a) -> a + 16

    .then_do ->
        console.log 'finding spike...'

        ratio = transform_size/60/sample_rate * downsample_ratio
        min = Math.floor 200 * ratio
        max = Math.floor 300 * ratio
        echoes = 4 # TODO: Try different echoes, guess time signature PAH POW

        sample = Array.prototype.slice.call(frequencies)[..max]

        spike = sample.reduce (max, val, index) ->

            return max if index < min

            sum = ( sample[Math.floor index*a/echoes] for a in [1..echoes] ).reduce (a, b) -> a + b
            sum /= echoes

            if max[0] >= sum
                return max
            else
                return [ sum, index ]

        , [ 0, 0 ]

        bpm = spike[1]/ratio

        console.log 'spike:', spike
        console.log 'BPM:', bpm

        spike_phases = ( phases[Math.floor spike[1]*a/echoes]*echoes % Math.PI for a in [1..echoes] )
        console.log 'phases:', spike_phases

        draw_frequencies frequencies, colour: 'rgba(0, 0, 0, 1)', detail: downsample_ratio/8
        draw_frequencies phases, colour: 'rgba(0, 0, 255, 0.15)', detail: downsample_ratio/8

        draw_queue.then_do ->

            canvas = $('#frequencies canvas')[0]
            context = canvas.getContext '2d'
            context.strokeStyle = 'rgba(255, 0, 0, 0.15)'

            for a in [1..echoes]
                context.beginPath()
                context.moveTo a/echoes*spike[1]*8/downsample_ratio, -512
                context.lineTo a/echoes*spike[1]*8/downsample_ratio, 512
                context.stroke()

    .then_do ->
        time 'fft transform', ->
            [ test_real, test_imag ] = fft(imaginary(test), 0, test.length)

    .then_do ->
        time 'modulus', ->
            test_freq = combine test_real, test_imag, modulus

    .then_do ->
        time 'find max', ->
            max = Array.prototype.slice.call(test_freq).reduce (max, a, index) ->
                if max[0] >= a
                    return max
                else
                    return [ a, index ]
            , [ 0, 0 ]
            console.log 'max:', max

    .then_do ->
        time 'fft transform 2', ->
            [ test_imag, test_real ] = fft([ test_imag, test_real ], 0, test.length)

    .then_do ->
        draw_waveform test_real, colour: 'rgba(255, 0, 0, 0.5)', detail: draw_detail

    .then_do -> wave_draw.then_do -> console.log 'all done'

beat_ball = null # This will contain the interval used to perform animations
music_source = null # This is used to keep reference to the only source of music playing

process_file = (file) ->
    
    [ data, downsample_ratio, buffer, sample_rate, convolution, envelope, transform_real, transform_imag,
    frequencies, phases, bpm, echoes, position, beat_positions, beat_frequencies, beat_phases, beat_real, beat_imag ] = []

    transform_size = 1024*1024

    begin().then ->
        get_channel_data file, @callback

    .then_do (channel_data, audio_buffer) ->

        downsample_ratio = Math.floor channel_data.length/transform_size
        console.log 'Downsampling by factor of', downsample_ratio
        data = downsample channel_data, downsample_ratio

        sample_rate = audio_buffer.sampleRate
        buffer = audio_buffer

    .then_do ->
        draw_waveform data, colour: 'rgba(0, 0, 0, 0.15)', detail: data.length/MAX_CANVAS_WIDTH

    .then_do ->
        console.log 'convolving...'
        convolution = convolve data, hilbert_transform

    .then_do ->
        console.log 'enveloping...'
        envelope = combine data, convolution, modulus

    .then_do ->
        draw_waveform envelope, colour: 'rgba(255, 0, 0, 0.15)', detail: data.length/MAX_CANVAS_WIDTH

    .then_do ->
        console.log 'transforming...'
        [ transform_real, transform_imag ] = fft(imaginary(envelope), 0, transform_size)

    .then_do ->
        console.log 'absoluting...'
        frequencies = combine transform_real, transform_imag, modulus
        phases = combine transform_real, transform_imag, argument

    .then_do ->
        console.log 'finding best harmonic...'

        ratio = transform_size/60/sample_rate * downsample_ratio
        min = Math.floor 30 * ratio
        max = Math.floor 200 * ratio

        { echoes, position } = (find_best_harmonic(frequencies, echoes, min, max) for echoes in [3..23]).reduce (best, next, index) ->
            console.log next.position/ratio, next
            if next.likelihood > best.likelihood
                return next
            else if next.likelihood == best.likelihood and next.score > best.score
                return next
            else
                return best
        , score: 0, likelihood: 0

        bpm = position/ratio
        beat_positions = ( Math.floor(a/echoes*position) for a in [1..echoes] )

        console.log 'harmonic found:', echoes, position
        console.log 'BPM:', bpm
        console.log "Time Signature: #{echoes}/4"
        console.log 'phases:', ( phases[a] for a in beat_positions )

        $('#clock .bpm').text("#{ Math.floor bpm + 0.5 } bpm")
        $('#clock .time-signature').text("#{ echoes } / 4")

        draw_frequencies frequencies, colour: 'rgba(0, 0, 0, 1)', detail: downsample_ratio/8
        draw_frequencies phases, colour: 'rgba(0, 0, 255, 0.15)', detail: downsample_ratio/8

        draw_queue.then_do ->

            canvas = $('#frequencies canvas')[0]
            context = canvas.getContext '2d'
            context.strokeStyle = 'rgba(255, 0, 0, 0.15)'

            for a in beat_positions
                context.beginPath()
                context.moveTo a*8/downsample_ratio, -512
                context.lineTo a*8/downsample_ratio, 512
                context.stroke()

    .then_do ->
        console.log 'generating beat wave...'

        beat_real = map transform_real, (a, i) -> if i in beat_positions then a else 0
        beat_imag = map transform_imag, (a, i) -> if i in beat_positions then a else 0

        [ beat_imag, beat_real ] = fft [ beat_imag, beat_real ], 0, beat_real.length

        beat = combine beat_imag, beat_real, (a, b) -> a - b
        beat_magnitude = ( frequencies[a] for a in beat_positions ).reduce (a, b) -> a + b

        draw_waveform beat, colour: 'rgba(0, 255, 255, 1)', detail: data.length/MAX_CANVAS_WIDTH, adjust: false, scale: 512*512/beat_magnitude

        console.log 'playing song...'

        music_source?.stop()
        music_source = window.audio_context.createBufferSource()
        music_source.buffer = buffer
        music_source.connect window.audio_context.destination
        music_source.start 0

        begin_time = Date.now()

        time_ratio = sample_rate/(downsample_ratio*1000)
        bounce_height = 256*256/beat_magnitude

        clearInterval beat_ball
        beat_ball = setInterval ->

            time = Date.now() - begin_time
            sample_index = Math.floor time*time_ratio

            $('#beat-ball .real').css bottom: beat_real[sample_index] * bounce_height
            $('#beat-ball .imag').css bottom: beat_imag[sample_index] * bounce_height
            $('#beat-ball .both').css bottom: (beat_imag[sample_index] - beat_real[sample_index]) * bounce_height 

            hand_angle = phases[beat_positions[0]] + Math.PI*2*( (time-100) * time_ratio * (position/echoes) / transform_size )
            hand_angle = Math.floor(hand_angle*echoes/(Math.PI*2)) / echoes * Math.PI * 2

            $('#clock .hand').css transform: "rotate(#{ hand_angle }rad)"

        , 1000/60

    .then_do -> draw_queue.then_do -> console.log 'all done'

$ ->

    window.audio_context = new AudioContext()

    # test()

    on_drop '#drop-zone', (event) ->

        clear_canvases()

        for file in event.originalEvent.dataTransfer.files
            process_file file

        return
