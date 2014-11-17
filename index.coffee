MAX_CANVAS_WIDTH = 32767

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

get_channel_data = (file, callback) ->
    
    reader = new FileReader()
    reader.readAsArrayBuffer(file)
    console.log 'loading file', file
    reader.onloadend = ->
        console.log 'decoding file', file
        window.audio_context.decodeAudioData reader.result, (buffer) ->
            console.log 'done', buffer
            callback buffer.getChannelData(0)

convolve = (data, func, range = 64) ->
    
    response = for a in [-range...range]
        func(a) ? 0
    
    convolution = new Float32Array(data.length) # Initialises to 0
    
    for signal, signal_index in data

        continue if signal_index - range < 0
        continue if signal_index + range >= data.length

        for filter, filter_index in response
            convolution[signal_index] += data[signal_index + filter_index - range] * filter

    return convolution

combine = (data1, data2, func) ->

    result = new Float32Array(data1.length)

    for d, index in data1
        result[index] = func d, data2[index]

    return result

map = (data, func) ->
    
    result = new Float32Array(data.length)

    for d, i in data
        result[i] = func d

    return result

draw_line = (data, context, scale, detail, callback) ->

    chunk = 32
    index = 0

    interval = setInterval ->

        context.beginPath()
        context.moveTo (index-1)/detail, (data[index-1] ? 0) * scale

        for a in [index .. index + detail * chunk]
            context.lineTo a/detail, data[a] * scale

        context.stroke()

        index += detail * chunk

        if index >= data.length or index/detail > MAX_CANVAS_WIDTH
            clearInterval interval
            context.restore()
            callback?()

    , 0

draw_waveform = (data, colour, callback) ->

    detail = 256

    canvas = $('#waveform canvas')[0]
    canvas_width = Math.min MAX_CANVAS_WIDTH, Math.floor(data.length/detail)
    canvas.width = canvas_width if canvas.width != canvas_width

    context = canvas.getContext '2d'
    context.save()
    context.translate 0, 256
    context.scale 1, -1
    context.strokeStyle = colour

    draw_line data, context, 256, detail, callback

draw_frequencies = (data, colour, callback) ->
    
    detail = 0.125

    canvas = $('#frequencies canvas')[0]
    canvas_width = Math.min MAX_CANVAS_WIDTH, Math.floor(data.length/detail)
    canvas.width = canvas_width if canvas.width != canvas_width

    context = canvas.getContext '2d'
    context.save()
    context.translate 0, 512
    context.scale 1, -1
    context.strokeStyle = colour

    draw_line data, context, 16, detail, callback

fft = (data, from, count, step = 1) ->

    if count == 1
        return [ new Float32Array([ data[0][from] ]), new Float32Array([ data[1][from] ]) ]

    half_count = count/2

    [ first_half_real, first_half_imag ] = fft(data, from, half_count, step*2)
    [ second_half_real, second_half_imag ] = fft(data, from + step, half_count, step*2)

    result_real = new Float32Array(count)
    result_imag = new Float32Array(count)

    for k in [0...half_count]

        angle = -2 * Math.PI * k/count
        twiddle = [ Math.cos(angle), Math.sin(angle) ]
        scale = 1/Math.sqrt(2)

        rr = twiddle[0] * second_half_real[k]
        ri = twiddle[0] * second_half_imag[k]
        ir = twiddle[1] * second_half_real[k]
        ii = twiddle[1] * second_half_imag[k]

        result_real[k] = (first_half_real[k] + rr - ii) * scale
        result_imag[k] = (first_half_imag[k] + ri + ir) * scale

        result_real[k+half_count] = (first_half_real[k] - (rr - ii)) * scale
        result_imag[k+half_count] = (first_half_imag[k] - (ri + ir)) * scale

    return [ result_real, result_imag ]

imaginary = (data) -> [ data, new Float32Array(data.length) ]

time = (message, func) ->
    console.log "Starting #{message}"
    begin = Date.now()
    func()
    console.log "#{message} took #{Date.now() - begin}"

$ ->

    window.audio_context = new AudioContext()

    test = ( (if a == 0 then 1 else Math.sin(2*Math.PI*a/8)/(2*Math.PI*a/8)) for a in [-512*1024...512*1024] )
    # test = [ 0, 1, 0, -1, 0, 1, 0, -1 ]

    draw_waveform test, 'rgba(0, 0, 0, 0.5)', ->

        [ test_real, test_imag, test_freq ] = []

        time 'fft transform', ->
            [ test_real, test_imag ] = fft(imaginary(test), 0, test.length)

        time 'modulus', ->
            test_freq = combine test_real, test_imag, (a, b) -> Math.sqrt a*a + b*b

        draw_frequencies test_freq, 'rgba(0, 0, 0, 0.5)', ->

            max = Array.prototype.slice.call(test_freq).reduce (max, a, index) ->
                if max[0] >= a
                    return max
                else
                    return [ a, index ]
            , [ 0, 0 ]
            console.log 'max:', max

            time 'fft transform 2', ->
                [ test_imag, test_real ] = fft([ test_imag, test_real ], 0, test.length)

            draw_waveform test_real, 'rgba(255, 0, 0, 0.5)', ->
                console.log 'done'
      
    on_drop '#drop-zone', (event) ->

        for file in event.originalEvent.dataTransfer.files

            get_channel_data file, (data) ->

                draw_waveform data, 'rgba(0, 0, 0, 0.15)', ->

                    console.log 'convolving...'
                    convolution = convolve data, (x) ->
                        if x % 2 == 0
                            0
                        else
                            1/(Math.PI*x)

                    console.log 'enveloping...'
                    envelope = combine data, convolution, (a, b) -> Math.sqrt a*a + b*b

                    draw_waveform envelope, 'rgba(255, 0, 0, 0.15)', ->

                        console.log 'transforming...'
                        [ transform_real, transform_imag ] = fft(imaginary(envelope), 0, 1024*1024)

                        console.log 'absoluting...'
                        frequencies = combine transform_real, transform_imag, (a, b) -> Math.sqrt a*a + b*b

                        console.log 'finding spike...'
                        sample = Array.prototype.slice.call(frequencies)[12..120]
                        spike = sample.reduce (max, val, index) ->
                            if max[0] >= val
                                return max
                            else
                                return [ val, index + 12 ]
                        , [ 0, 0 ]
                        console.log 'spike:', spike
                        console.log sample

                        draw_frequencies frequencies, 'rgba(0, 0, 0, 1)', ->
                            console.log 'all done'

        return
