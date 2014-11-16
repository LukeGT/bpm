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
    
    convolution = new Float32Array(data.length)
    
    for signal, signal_index in data

        convolution[signal_index] = 0

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

draw_line = (data, context, scale, detail, callback) ->

    chunk = 32

    index = 0

    interval = setInterval ->

        context.beginPath()
        context.moveTo index/detail, (data[index-1] ? 0) * scale

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
    
    detail = 1

    canvas = $('#frequencies canvas')[0]
    canvas_width = Math.min MAX_CANVAS_WIDTH, Math.floor(data.length/detail)
    canvas.width = canvas_width if canvas.width != canvas_width

    context = canvas.getContext '2d'
    context.save()
    context.translate 0, 512
    context.scale 1, -1
    context.strokeStyle = colour

    draw_line data, context, 1, detail, callback

# TODO: Actually use imaginary numbers, and calculate the absolute value of each result at the end... FUCK

fft = (data, from, count, step = 1) ->

    if count == 1
        return [ new Float32Array([ data[from] ]), new Float32Array([ 0 ]) ]

    [ first_half_real, first_half_imag ] = fft(data, from, count/2, step*2)
    [ second_half_real, second_half_imag ] = fft(data, from + step, count/2, step*2)

    result_real = new Float32Array(count)
    result_imag = new Float32Array(count)

    for k in [0...count/2]

        twiddle = [ Math.cos(-2 * Math.PI * k/count), Math.sin(-2 * Math.PI * k/count) ]

        result_real[k] = first_half_real[k] + twiddle[0] * second_half_real[k]
        result_imag[k] = first_half_imag[k] + twiddle[1] * second_half_imag[k]

        result_real[k+count/2] = first_half_real[k] - twiddle[0] * second_half_real[k]
        result_imag[k+count/2] = first_half_imag[k] - twiddle[1] * second_half_imag[k]

    return [ result_real, result_imag ]

$ ->

    window.audio_context = new AudioContext()

    # test = ( Math.sin(2*Math.PI*a/17) for a in [0...1024] )
    # [ test_real, test_imag ] = fft(test, 0, 1024)
    # test_freq = combine test_real, test_imag, (a, b) -> Math.sqrt a*a + b*b
    # draw_frequencies test_freq, 'rgba(0, 0, 0, 0.15)', ->
    #     console.log 'test!', Array.prototype.slice.call(test_freq).reduce (max, a, index) ->
    #         if max[0] >= a
    #             return max
    #         else
    #             return [ a, index ]
    #     , [ 0, 0 ]
      
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
                        [ transform_real, transform_imag ] = fft(envelope, 0, 1024*1024)

                        console.log 'absoluting...'
                        frequencies = combine transform_real, transform_imag, (a, b) -> Math.sqrt a*a + b*b

                        console.log 'finding spike...'
                        spike = Array.prototype.slice.call(frequencies).reduce (max, val, index) ->
                            if max[0] >= val
                                return max
                            else
                                return [ val, index ]
                        , [ 0, 0 ]
                        console.log 'spike:', spike
                        console.log Array.prototype.slice.call(frequencies)[0..120]

                        draw_frequencies frequencies, 'rgba(0, 0, 0, 0.15)', ->
                            console.log 'all done'

        return undefined
