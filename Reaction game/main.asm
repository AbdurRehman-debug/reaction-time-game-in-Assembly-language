

.include "m328pdef.inc"

.def temp    = r16
.def temp2   = r17
.def cmp     = r22


.org 0x0000
    rjmp init


init:
    
    ldi temp, HIGH(RAMEND)
    out SPH, temp
    ldi temp, LOW(RAMEND)
    out SPL, temp


    ldi temp, (1<<PB0)|(1<<PB1)
    out DDRB, temp
    cbi PORTB, PB0
    cbi PORTB, PB1


    cbi DDRD, PD2
    cbi PORTD, PD2


    ldi temp, 0
    sts UBRR0H, temp
    ldi temp, 103
    sts UBRR0L, temp
    ldi temp, (1<<TXEN0)
    sts UCSR0B, temp
    ldi temp, (1<<UCSZ01)|(1<<UCSZ00)
    sts UCSR0C, temp


    ldi temp, (1<<CS01)|(1<<CS00) 
    out TCCR0B, temp


    ldi ZL, LOW(str_ready<<1)
    ldi ZH, HIGH(str_ready<<1)
    rcall print_str


loop:

    cbi PORTB, PB0
    rcall tone_stop


    ldi ZL, LOW(str_getready<<1)
    ldi ZH, HIGH(str_getready<<1)
    rcall print_str


    ldi r24, LOW(124)       ; 1000 Hz 
    ldi r25, HIGH(124)
    rcall play_tone
    rcall delay_200ms
    rcall tone_stop
    rcall delay_500ms


    in r16, TCNT0
    ldi r17, 15
    mul r16, r17            
    movw r24, r0            

    ldi r16, LOW(1000)
    ldi r17, HIGH(1000)
    add r24, r16
    adc r25, r17           
random_delay_loop:
    rcall delay_1ms
    sbiw r24, 1
    brne random_delay_loop


    sbi PORTB, PB0
    ldi r24, LOW(61)        ; 2000 Hz
    ldi r25, HIGH(61)
    rcall play_tone


    ldi r24, LOW(0)         
    ldi r25, HIGH(0)        
wait_press:
    sbic PIND, PD2          
    rjmp press_done
    rcall delay_1ms         
    adiw r24, 1             
    rjmp wait_press

press_done:
    ; digitalWrite(ledPin, LOW); noTone(buzzerPin);
    cbi PORTB, PB0
    rcall tone_stop


    push r24                
    push r25

    ldi ZL, LOW(str_reaction<<1)
    ldi ZH, HIGH(str_reaction<<1)
    rcall print_str_no_newline


    rcall print_uint16

  
    ldi ZL, LOW(str_ms<<1)
    ldi ZH, HIGH(str_ms<<1)
    rcall print_str

    pop r25                 ; Restore reaction time
    pop r24

    ; if (reactionTime < 200)
    ldi temp,  HIGH(200)
    ldi temp2, LOW(200)
    cp  r24, temp2
    cpc r25, temp
    brlo excellent

    ; else if (reactionTime < 400)
    ldi temp,  HIGH(400)
    ldi temp2, LOW(400)
    cp  r24, temp2
    cpc r25, temp
    brlo good

    rjmp slow

excellent:
    ldi ZL, LOW(str_excellent<<1)
    ldi ZH, HIGH(str_excellent<<1)
    rcall print_str
    ldi r24, LOW(61)        ; 2000 Hz
    ldi r25, HIGH(61)
    rcall play_tone
    rcall delay_100ms
    rcall tone_stop
    rjmp done_round

good:
    ldi ZL, LOW(str_good<<1)
    ldi ZH, HIGH(str_good<<1)
    rcall print_str
    ldi r24, LOW(103)       ; 1200 Hz
    ldi r25, HIGH(103)
    rcall play_tone
    rcall delay_200ms
    rcall tone_stop
    rjmp done_round

slow:
    ldi ZL, LOW(str_slow<<1)
    ldi ZH, HIGH(str_slow<<1)
    rcall print_str
    ldi r24, LOW(311)       ; 400 Hz
    ldi r25, HIGH(311)
    rcall play_tone
    rcall delay_400ms
    rcall tone_stop

done_round:
    ldi ZL, LOW(str_sep<<1)
    ldi ZH, HIGH(str_sep<<1)
    rcall print_str
    rcall delay_2000ms
    rjmp loop



play_tone:
    ldi temp, (1<<COM1A0)                   
    sts TCCR1A, temp
    ldi temp, (1<<WGM12)|(1<<CS11)|(1<<CS10); 
    sts TCCR1B, temp
    sts OCR1AH, r25                       
    sts OCR1AL, r24                         
    ret

tone_stop:
    clr temp
    sts TCCR1A, temp
    sts TCCR1B, temp
    cbi PORTB, PB1                          
    ret



delay_1ms:
    push r24
    push r25
    ldi r24, LOW(3994)
    ldi r25, HIGH(3994)
d1_loop:
    sbiw r24, 1
    brne d1_loop
    pop r25
    pop r24
    ret

delay_100ms:
    ldi temp, 100
d100_loop:
    rcall delay_1ms
    dec temp
    brne d100_loop
    ret

delay_200ms:  rcall delay_100ms
              rcall delay_100ms
              ret
delay_400ms:  rcall delay_200ms
              rcall delay_200ms
              ret
delay_500ms:  rcall delay_400ms
              rcall delay_100ms
              ret
delay_2000ms: ldi r18, 20
d2000_loop:   rcall delay_100ms
              dec r18
              brne d2000_loop
              ret


print_uint16:
    clr r18                 

    ldi r20, HIGH(10000)
    ldi r21, LOW(10000)
    rcall extract_digit

    ldi r20, HIGH(1000)
    ldi r21, LOW(1000)
    rcall extract_digit

    ldi r20, HIGH(100)
    ldi r21, LOW(100)
    rcall extract_digit

    ldi r20, HIGH(10)
    ldi r21, LOW(10)
    rcall extract_digit

    ldi r18, 1              
    ldi r20, 0
    ldi r21, 1
    rcall extract_digit
    ret

extract_digit:
    clr r19                 
ed_loop:
    cp r24, r21
    cpc r25, r20
    brlo ed_done            
    sub r24, r21           
    sbc r25, r20
    inc r19                 
    rjmp ed_loop
ed_done:
    tst r19
    brne ed_print           
    tst r18
    breq ed_skip            
ed_print:
    ldi r18, 1              
    ldi temp, '0'
    add temp, r19
    rcall uart_send
ed_skip:
    ret



print_str:
    rcall print_str_no_newline
    ldi  temp, 13
    rcall uart_send
    ldi  temp, 10
    rcall uart_send
    ret

print_str_no_newline:
    lpm  temp, Z+
    tst  temp
    breq ps_end
    rcall uart_send
    rjmp print_str_no_newline
ps_end:
    ret

uart_send:
    push cmp
us_wait:
    lds  cmp, UCSR0A
    sbrs cmp, UDRE0
    rjmp us_wait
    sts  UDR0, temp
    pop  cmp
    ret

; =========================================
; STRINGS & UTF-8 EMOJIS
; =========================================
str_ready:     .db "Reaction Game Ready...", 0, 0
str_getready:  .db "Get ready...", 0, 0
str_reaction:  .db "Reaction Time: ", 0
str_ms:        .db " ms", 0, 0
str_excellent: .db 0xF0, 0x9F, 0x94, 0xA5, " Excellent!", 0, 0   ; ??
str_good:      .db 0xF0, 0x9F, 0x9F, 0xA1, " Good", 0, 0         ; ??
str_slow:      .db 0xF0, 0x9F, 0x94, 0xB4, " Slow", 0, 0         ; ??
str_sep:       .db "-------------------", 0, 0