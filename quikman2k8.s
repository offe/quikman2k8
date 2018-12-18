; Quikman 2K8 for Commodore VIC20
; written by Robert Hurst <robert@hurst-ri.us>
; originally used Commodore VICMON (SYS 45056)
; updated version: 30-Nov-2008
;
; to assemble this source using cc65.org project:
;   ca65.exe --cpu 6502 --listing quikman2k8.s
;   ld65.exe -C doc/vic20.cfg -o quikman2k8.prg quikman2k8.o
;
; to run the binary using viceteam.org project:
;   xvic -memory none -ntsc -sound -joydev1 2 -autostart quikman2k8.prg
; to run the binary using mess.org project:
;   mess -view "Pixel Aspect (25:31)" vic20 -quik quikman2k8.prg
;
; pertinent VIC20 symbols
JIFFYH		= $A0		; jiffy-clock hi byte value
JIFFYM		= $A1		; jiffy-clock mid byte value
JIFFYL		= $A2		; jiffy-clock low byte value
CLRPAGE		= $F4		; color memory page (unexpanded = $97)
SCRNPAGE	= $0288		; screen memory page (unexpanded = $1E)
CTRLCSHIFT	= $028D		; keyboard flag: control/commodore/shift
CASSBUFF	= $033C		; cassette buffer
VIC			= $9000		; start of video interface chip registers
RESET		= $FD22		; warm startup
CHROUT		= $FFD2		; print character with cursor translation
GETIN		= $FFE4		; get a character from keyboard queue
;
; my symbol / memory map
;			= $00		; base index (monster, sprite)
;			= $01		; index x2
;			= $02		; index x8
PPILLTIMER	= $10		; powerpill effectiveness timer
FRUITTIMER	= $39		; 0 - 242
FRUITFLAG	= $3A		; zero or non-zero, if fruit has been activated
PPILLFLAG	= $3B		; just ate a powerpill this turn (0=no)
CHOMP		= $3C		; pointer into sound effect for fruit and fleeing monsters
CHEWING		= $3D		; flag whether quikman just ate a dot or not
DIGIT		= $3E		; award points at this digit place
POINTS		= $3F		; how many points scored
OLDDIR		= $40		; direction sprite was last moving in
NEWDIR		= $41		; direction sprite wants to take, if valid by MAZEMOVE
JOYVAL		= $42		; last joystick read value
QMANDIR		= $43		; quikman's current direction (0=right,1=down,2=left,3=up)
FRAME		= $44		; frame rate
LIVES		= $45		; 0 - 3
FLASHPILL	= $46		; powerpill blink counter (0-30)
EXTRAQMAN	= $47		; bonus quickman flag (0=unused)
DEMOQMAN	= $48		; spirit of quickman index (0-3)
FRUITLEVEL	= $49		; 0 - 12
DOTS		= $4A		; 0 - 174
PENALTY		= $4B		; $4B-$4E monsters are free-to-roam flag
;			= $4F		; $4F-$52 monsters current direction (0=right,1=down,2=left,3=up)
;			= $53		; $53,$55,$57,$59 monster's knowledge of quikman's "X" coord was
;			= $54		; $54,$56,$58,$5A monster's knowledge of quikman's "Y" coord was
MONMOVE		= $61		; $61-$64 monster array for its next best move
;			= $69		; temporary var
FLEEINGSCORE= $70		; fleeing monster score: 2, 4, 8, 16
;			= $F7		; $F7/$F8,$F9,$FA are screen cell pointers for sprite's position
;			= $FE		; $FC/$FD,$FE/$FF are color cell pointers for same
;
; program indirects (my sprite registers)
SPRITE		= $02A1		; bitmask 0-7 controls sprite on/off
SPRITEX		= $02A2		; $02A2,A4,A6,A8,AA,AC,AE,B0 each "X" coordinate
SPRITEY		= $02A3		; $02A3,A5,A7,A9,AB,AD,AF,B1 each "Y" coordinate
SPRITECLR	= $02B2		; $02B2-$02B9 color
SPRITEIMG1	= $02BA		; $02BA-$02C1 low-byte of SPRITE image
SPRITEIMG2	= $02C2		; $02C2-$02C9 hi-byte of SPRITE image
SPRITELAST	= $02CC		; $02CC-$02DC keep last state of SPRITE registers
SAVEBACK	= $02DD		; $02DD-$02E6 keep what's under the sprite's 2-cell
;
; other constants
FRUITCELL	= $1F1B		; screen cell address of fruit
FRUITCELLCLR= $971B		; color cell address of fruit
;
; uses standard VIC20 (unexpanded)
		.org $0FFF
		.segment "STARTUP"
;
;********************************************************************
; LOAD "QUIKMAN2K8.PRG",8,1
		.word	$1001	; starting load address
BASIC:	.byte	$0B, $10
				; 2008 SYS4109
		.byte	$D8, $07, $9E, $34, $31, $30, $39
		.byte	$00, $00, $00
;
;********************************************************************
; Main entry point into the game
START:
		LDA #$08		; lock uppercase / graphic set
		JSR CHROUT
		LDA VIC+$01
		SBC #$04
		STA VIC+$01
		LDA #$80+$15	; set for videoram @ $1E00 with 21-columns
		STA VIC+$02		; video matrix address + columns
		LDA #$B0		; $B0 = 10110000 = 24 rows + 8x8 height
		STA VIC+$03		; rows / character height
		LDX #$FF		; set for $1C00
		STX VIC+$05		; use programmable char set
		JSR RESTORE
		LDX #$16
@loop:	LDA BANNERMSG-1,X
		STA BANNERMSG+$03FF,X
		LDA #$03
		STA BANNERMSG+$7BFF,X
		DEX
		BNE @loop
		SEI
		LDX #<BACKGROUND
		LDY #>BACKGROUND
		STX $0314		; enable my IRQ vector jump
		STY $0315
		CLI
;
RESTART:
		JSR INITVARS
		LDY #$00
		STY LIVES
		STY FRUITLEVEL
		JSR GAMEOVER
		LDY #$0A
		STY SPRITE
@loop:	LDA FRAME
		AND #$7F
		BNE @slow
		LDX VIC+$0F
		INX
		TXA
		AND #$07
		TAX
		ORA #$08
		STA VIC+$0F
		JSR MAZEPAINT
		LDA JIFFYM
		AND #$0F
		BNE @skip
		STX PPILLFLAG	; demo powerpill
@skip:	TAX
		CPX #$0D
		BCC @fruit
		LDX #$00
@fruit:	LDA FRUIT,X
		STA FRUITCELL
		LDA FRUITCLR,X
		STA FRUITCELLCLR
		LDA #$40
		STA FRUITTIMER
		STA FRUITFLAG
@slow:	LDX JIFFYL
		INX
		INX
@wait:	CPX JIFFYL
		BNE @wait
		LDA SPRITE
		EOR #$1E
		STA SPRITE
		JSR NPC			; demo mode
@scan:	JSR SPRITES
		JSR GETIN		; get keyboard
		CMP	#$03		; got STOP ?
		BNE @skip1
		JMP RESET		; bye-bye
@skip1:	CMP #$88		; got F7 ?
		BNE @loop		; try again ...
;
;********************************************************************
RESETGAME:
		JSR INITVARS
		LDA #$03		; start with 3-lives
		STA LIVES
		LDY #$FF		; -1 will become 0 at start of "next" level
		STY FRUITLEVEL
		JSR GAMEOVER	; clear status
		LDX #$00		; reset score
		STX EXTRAQMAN	; reset bonus
@loop1:	LDA #$B0		; each digit to "0"
		STA SCORE,X		; into savebuffer
		INX				; do next digit
		CPX #$06		; all 6 of them
		BNE @loop1
;
STARTLVL:
		JSR RESTORE		; initialize new level
;
RESETCHR:
		LDX #$00
		STX QMANDIR		; start off going RIGHT
		STX JOYVAL		; preload last joystick value as going RIGHT
@loop1:	LDA STARTPOS,X	; reset each sprite starting position
		STA SPRITEX,X
		INX
		CPX #$0A		; 5 sprites per X,Y coordinate pair
		BNE @loop1
		LDA #$1D		; 2nd page where quikman is on
		STA SPRITEIMG2
		LDA #$08		; start quikman off with a smug smile
		STA SPRITEIMG1
		LDA #$1F		; turn on sprites 0-4
		STA SPRITE
		LDA #$40
		JSR PAUSE		; then he sees there are monsters ...
		LDX #$05
@loop2:	LDA $C377,X		; print READY from ROM
		AND #$BF
		ORA #$80
		STA $1F18,X
		LDA #$07		; make it yellow
		STA $9718,X
		DEX
		BNE @loop2		; how geeky is that?
		LDA #$58		; quikman gets ready
		STA SPRITEIMG1
		LDA #$A0
		JSR PAUSE		; wait 2+ seconds
		LDX #$00
		LDA #$20		; erase READY
@loop4:	STA $1F19,X
		INX
		CPX #$05
		BNE @loop4
;
; zero $39 - $43
ZEROVARS:
		LDY #$39
		LDX #$00
@loop:	STX $00,Y
		INY
		CPY #$44
		BNE @loop
;
;********************************************************************
PLAYLOOP:
		LDA CTRLCSHIFT	; is the player holding down any
		BNE PLAYLOOP	; control, commodore, shift key(s)?
		LDA FRUITCELL
		CMP #$22		; is there fruit on display?
		BCC @warp
		LDX FRUITLEVEL
		LDA FRUITCLR,X	; restore fruit color
		STA FRUITCELLCLR
@warp:	LDA #$0C		; 10-levels to warp
		SEC
		SBC FRUITLEVEL	; progressive speed
		BCC @cruz
		CMP #$03
		BCS @pace
@cruz:	LDA #$03
@pace:	JSR SLOWDOWN
		STA $00			; quikman is sprite #0
		STA $01
		LDA QMANDIR
		STA OLDDIR		; save last direction quikman was going in
		LDX JOYVAL		; recall last joystick value
		STY $9113
		LDA #$7F
		STA $9122
		LDA $9120
		AND #$80		; JOY 3
		BNE @joy0
		LDX #$00
@joy0:	LDA #$FF
		STA $9122
		LDY $9111
		TYA
		AND #$08
		BNE @joy1
		LDX #$01
@joy1:	TYA
		AND #$10
		BNE @joy2
		LDX #$02
@joy2:	TYA
		AND #$04
		BNE @joy3
		LDX #$03
@joy3:	STX JOYVAL		; save
		TXA
		STA NEWDIR		; do the same for the joystick
		JSR MAZEMOVE
		BCS @skip1		; is the direction valid?
		LDA JOYVAL		; yes,
		STA QMANDIR		; request quikman to move in direction of joystick
		CLC
		BCC @skip2
@skip1:	LDA QMANDIR
		STA NEWDIR
		JSR MAZEMOVE	; keep the current direction going?
@skip2:	LDA SPRITEX
		BNE @skip3		; is quikman at end of tunnel left?
		LDA #$9E
		STA SPRITEX		; put quikman at beginning of tunnel right
@skip3:	CMP #$A0		; is quikman at end of tunnel right?
		BNE @skip4
		LDA #$00
		STA SPRITEX		; put quikman at beggining of tunnel left
@skip4:	LDX #$00		; use X as a flag
		LDA SPRITEX
		AND #$07
		CMP #$04
		BNE @skip5		; is quikman in the middle of a left/right cell?
		INX
		LDA QMANDIR		; yes, 0=right, 2=left
		EOR #$02
		TAY
		BEQ @skip6		; going left, use 1st saveback cell
		DEY
		BNE @skip6		; going right, use overflow saveback cell
@skip5:	LDA SPRITEY
		AND #$07
		CMP #$03
		BNE @skip6		; is quikman in the middle of an up/down cell?
		INX
		LDY QMANDIR
		CPY #$01		; going down, use overflow saveback cell
		BEQ @skip6
		LDY #$00		; going up, use 1st saveback cell
@skip6:	CPX #$00
		BNE @skip7		; does quikman have something in its mouth?
		JMP NPCNEXT		; no, continue play
@skip7:	LDA SAVEBACK,Y	; retrieve the character from quikman's saveback buffer
		CMP #$20
		BNE @skip8
		JMP PLAYLOOP	; nothing to eat here, so move a bit faster
		; check what was just eaten ...
@skip8:	TAX				; save that something in X
		LDA #$20
		STA SAVEBACK,Y	; replace the cell quikman is on with an empty space
		CPX #$1E		; is it a dot?
		BNE POWERUP
		LDA #$01
		STA POINTS		; score 1
		STA CHEWING		; quikman has to chew this dot, monsters keep movin'
		LDA #$0A		; score it @ 10-point digit
		STA DIGIT
;
POWERUP:
		CPX #$22
		BCC @skip1		; is X < 34 ?
		CPX #$2A		; no, is X >= 42 ?
		BCS NPCNEXT		; ate a piece of fruit?
		TXA				; YUMMY!
		SEC
		SBC #$22		; strip off char code for score index
		TAX
		LDA FRUITSCORE,X
		STA POINTS		; award points
		LDA #$09
		STA DIGIT		; in hundreds
		STA CHOMP
		CLC
		BCC NPCNEXT
@skip1:	CPX #$1F		; ate a powerpill?
		BNE EATING		; no, but I did eat a dot
		LDA #$05
		STA POINTS		; award 5-points
		LDA #$0A
		STA DIGIT		; score @ 10-digit
		STA PPILLFLAG
		BEQ NPCNEXT		; powerpills are dots on steroids, account for it
;
EATING:	INC DOTS		; ate a dot, account for it
		LDA DOTS
		CMP #$AA		; are all dots eaten?
		BNE NPCNEXT
;===	achieved end of level	===
WONLEVEL:
		LDA #$08		; quikman ends with a smug smile
		STA SPRITEIMG1
		LDA #$80
		JSR PAUSE
		STA FRAME
@loop:	DEC FRAME
		LDA FRAME
		AND #$07
		TAX
		JSR MAZEPAINT
		TXA
		AND #$1F
		BNE @next
		LDA SPRITE
		EOR #$1E
		STA SPRITE		; blink monsters
		JSR SPRITES
@next:	LDA FRAME
		CMP #$06
		BNE @loop		; continue until true blue
		LDA #$40
		JSR PAUSE
		JSR INITVARS
		LDX #$04
@loop1:	LDA PENALTY-1,X
		LDY FRUITLEVEL
		INY
@loop2:	LSR
		DEY
		BNE @loop2
		STA PENALTY-1,X		; after each level, the monsters dispatch quicker
		DEX
		BNE @loop1
		JMP STARTLVL
;
NPCNEXT:
		JSR GETIN		; get keyboard
		CMP	#$03		; got STOP ?
		BEQ WONLEVEL	; CHEATER!!
		JSR NPC
		LDX #$50		; closed mouth
		LDA SPRITEX
		ORA SPRITEY
		AND #$02
		BNE @anim
		LDA QMANDIR		; take 0=right,1=down,2=left,3=up value
		ASL				; multiply by 8 to get address
		ASL
		ASL
		CLC
		ADC #$58		; add base offset
		TAX
@anim:	STX SPRITEIMG1
		JSR SPRITES
		JMP PLAYLOOP
;
;********************************************************************
; non-player characters & events
NPC:
		LDA FRUITFLAG
		BNE @skip3		; is fruit already on display?
		LDA DOTS
		CMP #$4B		; has the 75th dot been eaten?
		BEQ @skip1
		CMP #$7D		; has the 125th dot been eaten?
		BNE @skip3
@skip1:	LDX FRUITLEVEL	; prepare thy bonus
		CPX #$0C		; reach the last level?
		BCC @skip2
		LDX #$0C		; only the key is left, and it leaves a bad metallic after-taste
@skip2:	LDA FRUIT,X
		STA FRUITCELL	; display fruit
		LDA FRUITCLR,X
		STA FRUITCELLCLR
		LDA #$FA		; 250-moves and counting
		STA FRUITTIMER	; reset fruit timer
		STA FRUITFLAG
@skip3:	LDA FRUITTIMER	; fruit is on display
		BEQ @skip4		; nothing to do
		DEC FRUITTIMER	; remove a tick
		BNE @skip4		; there is still time left
		LDA #$20		; time's up!
		STA FRUITCELL	; no more fruit
@skip4:	LDA DOTS
		CMP #$4C		; has the 76th dot been eaten?
		BEQ @skip5
		CMP #$7E		; has the 126th dot been eaten?
		BNE @skip6
@skip5:	LDA #$00
		STA FRUITFLAG	; more fruit potential on this level
;
@skip6:	LDA PPILLFLAG
		BEQ KISSING		; just swallowed a powerpill?
		LDA #$00		; account for that action
		STA PPILLFLAG
		LDA #$02		; start scoring @ 200-points
		STA FLEEINGSCORE
		LDX FRUITLEVEL
		TXA
		AND #$07
		BEQ @break		; every 8-levels, keep timer up
		CPX #$10
		BCS @timer		; 16-levels of powerpill timing
		TXA
@break:	ASL				; x2
		ASL				; x2
		AND #$3F
		EOR #$3F		; invert A
		CPX #$05
		BCC @timer		; timer good to the 1st apple
		LSR				; 1/2
@timer:	STA PPILLTIMER	; set powerpill timer
		LDY #$04
@loop1:	LDX PENALTY-1,Y
		BNE @skip7		; is monster waiting in cage already?
		LDA #$06		; no, make monster blue
		STA SPRITECLR,Y
		LDA #$80		; make monster fleeing (0)
		STA SPRITEIMG1,Y
		LDA $4E,Y
		EOR #$02		; and reverse its direction
		STA $4E,Y
@skip7:	DEY
		BNE @loop1
;
; check all monsters if any are in contact with quikman
KISSING:
		LDY #$08
KISSME:
		LDA SPRITEX
		CMP SPRITEX,Y
		BNE @skip3
		LDA SPRITEY
		SEC
		SBC SPRITEY,Y
		BCS @skip2
		EOR #$FF
@skip2:	CMP #$05
		BCS @skip3
		LDX #$FF
		BNE ENGAGED		; is quikman engaged with a monster?
@skip3:	LDA SPRITEY
		CMP SPRITEY,Y
		BNE NEXTKISS
		LDA SPRITEX
		SEC
		SBC SPRITEX,Y
		BCS @skip4
		EOR #$FF
@skip4:	CMP #$05
		BCC ENGAGED		; is quikman engaged with a monster?
;
NEXTKISS:
		DEY				; next monster
		DEY				; X,Y coord pair check
		BNE KISSME
		JMP MONSTERS	; quikman is still freely running!
;
ENGAGED:
		TYA
		LSR
		TAX
		LDA SPRITEIMG1,X
		CMP #$80		; is monster fleeing?
		BNE DEAD		; no, quikman bites the dust
		LDA #$09		; ahah!  caught a little sickly one!
		STA DIGIT		; in hundreds
		LDA FLEEINGSCORE
		STA POINTS		; fleeing monster score
		ASL				; next is worth x2 bonus
		STA FLEEINGSCORE
		LDA #$78
		STA SPRITEIMG1,X ; reset monster as chasing
		LDA #$51		; reset "X" coord in cage
		STA SPRITEX,Y
		LDA #$58		; reset "Y" coord in cage
		STA SPRITEY,Y
		LDA #$09
		STA CHOMP
		LDA JIFFYL
@loop1:	CMP JIFFYL
		BEQ @loop1		; wait up to a jiffy
		DEX
		LDA MONSTERCLR,X
		STA SPRITECLR+1,X
		LDA CAGEDATA,X	; load waiting room time
		EOR #$FF
		LSR
		ADC #$20
		STA PENALTY,X	; monster is waiting
		JMP NEXTKISS	; is there another monster here?
;
DEAD:
		PLA				; remove quikman's call to NPC from stack
		PLA				; because he just died . . .
		LDA #$30
		JSR PAUSE
		; death sequence
		LDA #$01		; only feature quikman dying
		STA SPRITE
		LDA #$50		; low-order byte of 1st quikman image
		STA SPRITEIMG1
		LDA #$20
		STA FRAME		; rotate quikman 8 times
@loop1:	LDA SPRITEIMG1
		CMP #$70		; are we at the 4th quikman image?
		BCC @skip
		LDA #$50		; reset to 1st quikman image
@skip:	CLC
		ADC #$08		; advance to next image
		STA SPRITEIMG1
		LDA #$04
		JSR PAUSE
		DEC FRAME
		BNE @loop1		; repeat next sequence
		LDX #$D8
		LDY #$1C
		STX SPRITEIMG1	; explode!
		STY SPRITEIMG2
		LDA #$0A
		JSR PAUSE
		LDX #$E0
		STX SPRITEIMG1	; smoke!
		LDA #$08
		JSR PAUSE
		LDX #$E8
		STX SPRITEIMG1	; dust!
		LDA #$06
		JSR PAUSE
		JSR INITVARS
		DEC LIVES
		BEQ FINALITY	; any lives remaining?
		LDX LIVES
		LDA #$1C
		STA $1FE4,X		; avatar smoking
		LDA #$08
		JSR PAUSE
		LDA #$20
		STA $1FE4,X		; erase the avatar
		JMP RESETCHR	; quikman still has life -- try again!
;
FINALITY:
		LDY LIVES
		STY SPRITE
		JSR GAMEOVER
		LDA #$F0		; 4-second pause
		JSR PAUSE
		JMP RESTART		; this game is really over now
;
;********************************************************************
MONSTERS:
		LDA #$04
		STA $00			; start with monster #4
;
DOMONSTER:
		LDA $00
		TAY
		ASL				; x2
		STA $01
		LDX PENALTY-1,Y
		BEQ ITMOVES		; is this monster free to roam?
		DEX				; no, countdown to freedom
		STX PENALTY-1,Y
;
NEXTMONSTER:
		DEC $00			; process next monster
		BNE DOMONSTER
		INC FRAME
		INC $00
		LDA SPRITEY+$02
		AND #$07
		ORA SPRITEX+$02
		AND #$0F
		BEQ DOMONSTER
		LDA CHEWING
		BNE @skip1		; is quikman eating a dot?
@fini:	RTS				; no, we're done
@skip1:	JSR SPRITES		; yes, chasing monsters get another turn
		JMP MONSTERS
;
ITMOVES:
		LDA FRAME
		AND #$01
		BEQ @cont		; powerpill active?
		LDA SPRITEIMG1,Y
		CMP #$80		; this monster IS fleeing
		BEQ NEXTMONSTER	; skip its turn
@cont:	LDX $01			; no, get pairing index
		LDA SPRITEX,X
		CMP #$50
		BNE @skip1
		LDA SPRITEY,X
		CMP #$58
		BNE @skip1		; is monster in cage ($50,$58 coord) doorway ?
		LDA #$57		; could have just used DEC SPRITEY,X instead
		STA SPRITEY,X	; move it a pixel UP to force it through the closed door
		LDX #$03
		STX $4E,Y		; make direction UP to get out of cage
		BNE @skip3
@skip1:	LDA SPRITEX,X
		BNE @skip2		; is monster against the left-side of the tunnel?
		LDX $00
		STA $4E,X		; force a change of direction to the right
@skip2:	CMP #$9F		; is monster against the right-side of the tunnel?
		BNE @skip3
		LDX $00
		LDA #$02
		STA $4E,X		; force a change of direction to the left
@skip3:	LDY #$00
		LDX #$04
@loop1:	STX MONMOVE-1,Y	; preset move priority as 0=right,1=down,2=left,3=up
		INY
		DEX
		BNE @loop1
		LDY $01			; start of monster's calculated move
		LDA SPRITEX,Y
		AND #$07
		BEQ @skip4		; is monster horizontally aligned with a screen cell?
		LDA SPRITEY,Y
		AND #$07
		BNE @skip5		; is monster vertically aligned with a screen cell?
@skip4:	JSR AI			; yes, check to see if a direction change is in its future
		CLC
		BCC @skip6
@skip5:	LDX $4E,Y		; not in a position to make a direction change,
		STX $61			; so just keep monster going in its current direction
@skip6:	LDY #$00
		STY $04
@loop2:	LDX $61,Y
		TXA
		LDX $00
		EOR $4E,X
		CMP #$02
		BEQ @skip7		; don't allow monsters to reverse direction on their own
		LDX $61,Y
		STX NEWDIR
		LDY $00
		LDX $4E,Y
		STX OLDDIR
		JSR MAZEMOVE	; validate
		BCC MAKEMOVE	; is this a good move?
@skip7:	INC $04
		LDY $04
		CPY #$04
		BNE @loop2
		LDY $00			; reverse direction
		LDA OLDDIR
		EOR #$02
		STA $4E,Y
		JMP NEXTMONSTER
;
MAKEMOVE:
		LDY $00			; commit to this move
		LDX NEWDIR
		STX $4E,Y		; save as monster's current direction
		JMP NEXTMONSTER
;
; monster's artificial intelligence
AI:
; first, preload $61-$64 with "best" moves this monster can make
; to give quikman the kiss of death
		LDX $01
		LDA $51,X		; retrieve this monster's "X" knowledge where quikman was
		SEC
		SBC SPRITEX,X
		BCS @skip1
		LDY #$02
		STY MONMOVE		; LEFT is best
		LDY #$00
		STY $64			; RIGHT is worst
		BEQ @skip2
@skip1:	LDY #$00
		STY MONMOVE		; RIGHT is best
		LDY #$02
		STY $64			; LEFT is worst
@skip2:	LDA $52,X		; retrieve this monster's "Y" knowledge where quikman was
		SEC
		SBC SPRITEY,X
		BCS @skip3
		LDY #$03
		STY $62			; UP is 2nd best
		LDY #$01
		STY $63			; DOWN is 3rd best
		BNE AI2
@skip3:	LDY #$01		; DOWN is 2nd best
		STY $62
		LDY #$03		; UP is 3rd best
		STY $63
;
; next, prioritize monster move, based upon its current location in respect to
; its knowledge where quikman was considered last.
AI2:	LDX $01
		LDA $51,X
		SEC
		SBC SPRITEX,X
		BCS @skip1
		EOR #$FF
@skip1:	STA $69
		LDA $52,X
		SEC
		SBC SPRITEY,X
		BCS @skip2
		EOR #$FF
@skip2:	CMP $69
		BCC @skip3		; can monster improve upon order of choices?
		LDX MONMOVE		; swap 1st & 2nd choices
		LDY $62
		STX $62
		STY MONMOVE
		LDY $63			; swap 3rd & 4th choices
		LDX $64
		STY $64
		STX $63
@skip3:	LDY $00
		LDA SPRITEIMG1,Y
		CMP #$80		; is this monster fleeing?
		BNE @fini		; no, chase!
		LDX #$04
@loop1:	LDA MONMOVE-1,X
		PHA
		DEX
		BNE @loop1
@loop2:	PLA
		STA $61,X		; reverse logic when in flee mode
		INX
		CPX #$04
		BNE @loop2
@fini:	RTS
;
INITVARS:
		LDY #$00
@loop:	LDX CAGEDATA,Y
		STX PENALTY,Y
		LDA STARTPOS,Y	; reset each sprite starting position
		STA SPRITEX,Y
		INY
		CPY #$10
		BNE @loop
		RTS
;
; restore sound/screen
RESTORE:
		INC FRUITLEVEL
		LDA #$00
		STA SPRITE		; turn off all sprites
		LDA #$0E		; black / blue
		STA VIC+$0F		; background / border color
		LDA #$AF		; pink & highest
		STA VIC+$0E		; auxiliary color & volume
		LDA #$93		; Shift-HOME is clearscreen
		JSR	CHROUT		; print it
		LDX #$15		; skip 1st & last row
@draw:	LDA MAZEDATA,X
		STA $1E00,X
		LDA MAZEDATA+$E3,X
		STA $1EE3,X
		INX
		BNE @draw
		STX DOTS		; and no dots are eaten (yet)
		LDX #$06		; blue
		JSR MAZEPAINT
		LDX #$00
@loop2:	LDA QUIKMANCLR,X ; reset monsters starting colors
		STA SPRITECLR,X ; into their sprite color registers
		LDA #$78		; reset monsters as chasing
		STA SPRITEIMG1,X
		LDA #$1D
		STA SPRITEIMG2,X
		INX
		CPX #$05
		BNE @loop2
		LDY LIVES		; paint lives remaining
		JSR GAMEOVER
		DEY
		BEQ @next
@loop4:	LDA #$2D		; quikman character
		STA $1FE4,Y		; bottom-left of screen
		LDA #$07		; use yellow
		STA $97E4,Y		; and paint it
		DEY
		BNE @loop4
@next:	LDY FRUITLEVEL
		LDX #$00
@loop5:	CPY #$0C		; are we at the last level (key)?
		BCC @skip1
		LDY #$0C		; only keys remain
@skip1:	LDA FRUIT,Y		; fruit character
		STA $1FF1,X		; bottom right of screen
		LDA FRUITCLR,Y	; get its color
		STA $97F1,X		; and paint it
		CPY #$00		; did we paint the cherry yet?
		BEQ BEGIN		; if so, we're done
		INX
		STX $FF
		LDA FRUITLEVEL
		SEC
		SBC $FF
		TAY
		CPX #$07		; no more than 7 fruits to display
		BNE @loop5
BEGIN:	;LDA LIVES		; allow new screen to be processed
		;BEQ @cont
		;LDA #$40
;@cont:	JSR PAUSE		; by player
		RTS
;
; recolor maze with some new paint in X
MAZEPAINT:
		LDY #$15
@loop:	LDA MAZEDATA,Y
		CMP #$31
		BCC @page2
		CMP #$3F
		BCS @page2
		LDA #$01
		TXA
		STA $9600,Y
@page2:	LDA MAZEDATA+$E3,Y
		CMP #$31
		BCC @skip
		CMP #$3F
		BCS @skip
		TXA
		STA $96E3,Y
@skip:	INY
		BNE @loop
		RTS
;
; if move is valid, carry flag will be clear on return
MAZEMOVE:
		LDY $01			; get X,Y coord index
		LDA OLDDIR		; get the last direction moving
		AND #$01		; mask UP/DOWN
		BEQ @skip1		; is direction LEFT/RIGHT?
		INY				; no, then fetch the "Y" coordinate
@skip1:	LDA SPRITEX,Y	; get one of sprite's coord
		AND #$07
		BEQ MAZEANY		; at a crossroad?  check move in any 4-directions
		LDA NEWDIR
		CMP OLDDIR
		BEQ MYMOVE		; still want to move in the same direction?
		EOR OLDDIR
		CMP #$02
		BEQ MYMOVE		; is this a reverse direction request?
		SEC				; no new move made
		RTS
;
MAZEANY:
		JSR SPRITEPREP
		LDA $F8			; reset screen hi-byte back into saved maze data
		SEC
		SBC #$04
		STA $F8
		LDX NEWDIR
		CPX #$02
		BCS @skip2		; is X (2=left) or (3=up)?
		LDA $F7			; no
		CLC
		ADC PEEKAHEAD,X	; look (0=right) or (1=down)
		BCC @skip1
		INC $F8
@skip1:	STA $F7
		CLC
		BCC @skip4		; go validate
@skip2:	LDA $F7
		SEC
		SBC PEEKAHEAD-2,X
		BCS @skip3		; look (2=left) or (3=up)
		DEC $F8
@skip3:	STA $F7
@skip4:	LDY #$00		; validate
		LDA ($F7),Y
		CMP #$31		; is this direction into a maze wall?
		BCC MYMOVE		; good move?
		RTS
;
; continue this sprite's move in whatever is loaded in NEWDIR
MYMOVE:
		LDA NEWDIR
		ASL				; 0=0, 1=2, 2=4, 3=6, 4=8
		TAX
		LDY $01
		LDA INERTIA,X
		CLC
		ADC SPRITEX,Y
		STA SPRITEX,Y
		LDA INERTIA+1,X
		CLC
		ADC SPRITEY,Y
		STA SPRITEY,Y
		CLC
		RTS
;
;********************************************************************
; my very own sprite routines
; major custom hack for this maze game implementation
SPRITES:
		LDA #$00		; start with sprite #0
		STA $00			; current sprite # to render
@loop1:	ASL
		STA $01			; current sprite (x2) pairing index
		ASL
		ASL
		STA $02			; current sprite (x8) image index
		LDX $00
		LDA SPRITE
		AND SPRITEMASK,X
		BEQ @skip2		; nothing to do?
		LDA SPRITELAST	; what state was this sprite before?
		AND SPRITEMASK,X
		BEQ @skip1		; it was "off"
		JSR ERASESPRITE	; was "on" before, and we still want it "on"
@skip1:	JSR SPRITEPREP	; new sprite, go turn it "on"
		JSR PREPMATRIX
		JSR RENDER
		JSR PLACEMATRIX
		JMP @next
@skip2:	LDA SPRITELAST
		AND SPRITEMASK,X
		BEQ @next		; still nothing to do?  Then do nothing ...
		JSR ERASESPRITE	; make this sprite disappear
@next:	INC $00
		LDA $00
		CMP #$05		; only 5-sprites needed in this game
		BNE @loop1
		LDX #$00
@loop2:	LDA SPRITE,X	; save copy of current sprite registers
		STA SPRITELAST,X
		INX
		CPX #$11		; all 17 values, not including colors
		BNE @loop2
		RTS				; fini
;
; remove sprite from screen
ERASESPRITE:
		JSR LASTSPRITEPREP
		JSR PREPMATRIX
		JSR RESTOREMATRIX
		RTS
;
LASTSPRITEPREP:
		LDA $01			; 0, 2, 4, 6, 8
		CLC
		ADC #<SPRITELAST
		BNE SPRITEPREP2
;
; prepares the following registers:
; $F7/$F8,$F9/$FA		screen cell pointers for sprite position
; $FC/$FD,$FE/$FF		color cell pointers for same
SPRITEPREP:
		LDA $01			; 0, 2, 4, 6, 8 index
		CLC
		ADC #<SPRITE
SPRITEPREP2:
		TAX				; save this register index
		LDA $0201,X		; get "X" coordinate
		CMP #$A0
		BCC @skip1		; is "X" at or beyond last column?
		SBC #$A0		; yes, subtract 160-pixels wide
@skip1:	LSR				; and divide by 8-pixel width
		LSR
		LSR
		STA $F7			; save column offset from left screen
		STA $FC			; save column offset from left color
		LDA SCRNPAGE	; get high order byte of screen memory page
		STA $F8
		LDA CLRPAGE		; get high order byte of screen color page
		AND #$FE		; make it and "even" number
		STA $FD			; save high order
		LDA $0202,X		; get "Y" coordinate
		CMP #$B8
		BCC @skip2		; is "Y" at or beyond last row?
		SBC #$B8		; yes, subtract 184-pixels high
@skip2:	LSR				; and divide by 8-pixel height
		LSR
		LSR
		TAY
		BEQ @fini		; if on top row, no math required
		LDA $F7			; get column offset
@loop1:	CLC
		ADC #$15		; add 21 for next row
		BCC @skip3		; overflow to next page?
		INC $F8			; yes, increment high order bytes
		INC $FD
@skip3:	STA $F7			; save column offset
		STA $FC
		DEY
		BNE @loop1		; do for each "row"
@fini:	LDA $F8			; copy high-order bytes
		STA $FA			; for overflow sprite character
		LDA $FD			; do the same
		STA $FF			; for color
; determine whether overflow character is to the right or down
		LDA $0201,X		; get "X" coordinate
		AND #$07
		BEQ @vert		; 0 assumes moving up/down?
		LDA $F7			; ok, moving left/right then ...
		CLC
		ADC #$01		; make overflow character to the right
		BCC @savel
@saveh:	INC $FA
		INC $FF
@savel:	STA $F9			; save character offset
		STA $FE			; save color offset
		RTS
@vert:	LDA $F7
		CLC
		ADC #$15		; make overflow character below
		BCC @savel
		BCS @saveh
;
; prepares saveback buffers for restoring, should a larger-numbered sprite be
; overlapping any part of a smaller-numbered sprite
PREPMATRIX:
		LDY #$00
		LDA ($F7),Y		; retrieve screen cell
		PHA
		LDY $01			; 0, 2, 4, 6, 8 index
		LDA $0201,X
		AND #$07
		BNE @2cell
		LDA $0202,X
		AND #$07
		BEQ @start
@2cell:	LDY #$00
		LDA ($F9),Y		; retrieve overflow cell
		PHA
		LDY $01			; 0, 2, 4, 6, 8 index
		INY
@start:	TYA
		TAX
@loop:	PLA
@retry:	CMP $01
		BCC @skip		; is A < ME ?
		CMP #$0A
		BCS @skip		; is A >= MAX ?
; there is a sprite # greater than us on top ...
		TAY
		LDA SAVEBACK,Y	; get > sprite# saveback info
		CLC
		BCC @retry
@skip:	STA SAVEBACK,X
		DEX
		CPX $01
		BEQ @loop
		RTS
;
; restores the sprite's saveback buffer to the screen squares it occupies
; erasure part 3
RESTOREMATRIX:
		LDX $01
		LDA SAVEBACK,X	; recover character
		LDY #$00
		STA ($F7),Y		; restore to screen
		LDA #$01
		STA ($FC),Y		; just leave "white" behind
		LDA SPRITELAST+1,X
		AND #$07
		BNE @2cell
		LDA SPRITELAST+2,X
		AND #$07
		BEQ @fini
@2cell:	LDA SAVEBACK+1,X
		STA ($F9),Y		; restore to screen
		LDA #$01
		STA ($FE),Y		; only color overflow if X or Y are offset
@fini:	RTS
;
; render sprite within its character matrix by merging its image over its saveback
; $05/$06 points to graphic character
RENDER:
		LDX $00			; 0-4
		LDA SPRITEIMG1,X
		STA $05
		LDA SPRITEIMG2,X
		STA $06
		LDX $01			; 0,2,4,6,8
		LDA SPRITEY,X
		AND #$07
		STA $03
		TAX				; X will hold the sprite's Y coord
		LDY #$00		; erase temp image matrix area
		TYA
@loop1:	STA CASSBUFF+$20,Y
		INY
		CPY #$10		; customized from 4 to 2 character cells
		BNE @loop1
		TAY				; copy 8x8 character image into temp matrix
@loop2:	LDA ($05),Y		; $05/$06 points to character matrix to draw
		STA CASSBUFF+$20,X
		INX
		INY
		CPY #$08
		BNE @loop2
		LDX $01
		LDA SPRITEX,X
		AND #$07		; get modulos on X coordinate
		TAY
		BEQ @skip1		; if its zero, no shifting required
@loop3:	LDX #$00
@loop4:	CLC
		ROR CASSBUFF+$20,X
		ROR CASSBUFF+$28,X
		INX
		CPX #$08
		BNE @loop4
		DEY
		BNE @loop3
@skip1:	STY $FB			; Y is always zero here
@loop5:	LDA $01			; index x2
		CLC
		ADC $FB
		TAX				; X is sprite custom character
		LDA #$1C		; 1st page is where sprites are stored
		STA $06
		LDA SAVEBACK,X
		CMP #$80
		BCC @skip2		; is character reversed?
		LDY #$80		; yes, use start of ROM character set
		STY $06
@skip2:	AND #$1F		; get modulos of first 32-characters
		ASL				; and multiply by 8-pixel height
		ASL
		ASL
		STA $05			; save as low-order byte index
		LDA SAVEBACK,X
		AND #$60		; mask 01100000
		LSR				; divide by 16
		LSR
		LSR
		LSR
		LSR
		CLC
		ADC $06			; add result to high-order page index
		STA $06
		LDY #$00
		LDA $FB
		ASL
		ASL
		ASL
		TAX
@loop6:	LDA ($05),Y		; copy 8x8 character image into behind matrix
		STA CASSBUFF+$30,X
		INX
		INY
		CPY #$08
		BNE @loop6
		INC $FB
		LDA $FB
		CMP #$02		; only a 2-cell sprite now
		BNE @loop5
		LDY #$00
		LDA $02			; 0, 8, 16, 24, 32
		ASL				; 0, 16, 32, 48, 64
		TAX
@loop7:	LDA	CASSBUFF+$20,Y
		ORA CASSBUFF+$30,Y
		STA $1C00,X
		INX
		INY
		CPY #$10		; customized from 4 to 2 character cells
		BNE @loop7
		RTS
;
; puts the sprite character matrix on the screen
PLACEMATRIX:
		LDA $01			; 0, 2, 4, 6, 8
		LDY #$00
		STA ($F7),Y
		LDX $00
		LDA SPRITECLR,X
		STA ($FC),Y
		LDX $01
		LDA SPRITEX,X
		AND #$07
		BNE @color
		LDA SPRITEY,X
		AND #$07
		BEQ @fini
@color:	LDA ($FC),Y
		STA ($FE),Y		; only color overflow if X & Y are offset
		INX
		TXA
		STA ($F9),Y
@fini:	RTS
;
;********************************************************************
; This section is dedicated to background processing, accomplished
; via the keyboard IRQ service, called 60-times per second (jiffy).
BACKGROUND:
		LDA $1EDC
		CMP #$C5
		BNE @esc
		LDA #$09
		STA $96DC		; paint the cage door
@esc:	LDA JIFFYL
		AND #$07
		BNE FLASH
		LDA PPILLTIMER	; drain powerpill
		BEQ FLASH		; is there still power left?
		CMP #$1F		; yes ... but are they
		BCS DRAIN		; getting confidence back?
		AND #$03		; yes, let's warn quikman
		BNE DRAIN
		LDY #$04
@pp1:	LDA SPRITEIMG1,Y
		CMP #$80		; is monster fleeing?
		BNE @pp2
		LDA SPRITECLR,Y
		EOR #$07		; flash white / blue
		STA SPRITECLR,Y
@pp2:	DEY
		BNE @pp1
DRAIN:	DEC PPILLTIMER
		BNE FLASH
		LDY #$04
@loop:	LDA MONSTERCLR-1,Y	
		STA SPRITECLR,Y	; restore all monsters to their default colors
		LDA #$78		; restore monster chasing image (/)
		STA SPRITEIMG1,Y
		DEY
		BNE @loop
FLASH:	LDA FLASHPILL	; powerpill flash
		CMP #$1E		; 30-jiffies?
		BNE @skip1
		LDX #$00		; reset counter
		STX FLASHPILL
@loop1:	LDA $1CF8,X		; custom graphic char
		EOR $8288,X		; rom graphic char
		STA $1CF8,X		; redraw 8x8 char cell
		INX
		CPX #$08
		BNE @loop1
		LDA #$FE		; render monster feet
		EOR $1D7F		; custom graphic char
		STA $1D7F		; redraw agressive monster
		STA $1D87		; redraw fleeing monster
@skip1:	INC FLASHPILL
		LDA LIVES
		BNE @hi			; playing?
		LDA JIFFYL		; manufacture a moving quikman 'spirit'
		AND #$03
		BEQ @hi
		CLC
		ADC JIFFYM
		AND #$03
		BEQ @hi
		INC DEMOQMAN
		LDA DEMOQMAN
		AND #$03
		ASL
		TAY				; for the monsters to 'chase'
		LDA CAGEDATA+$08,Y
		STA SPRITEX
		LDA CAGEDATA+$09,Y
		STA SPRITEY
@hi:	LDX #$00		; yes
@loop3:	LDA SCORE,X		; check current score against high score
		CMP MAZEDATA+$0F,X
		BCC @top		; is quikman beating the high score?
		BNE @skip4		; yes!
		INX
		CPX #$06
		BNE @loop3
@skip4:	LDX #$00
@loop4:	LDA SCORE,X		; woot!
		STA MAZEDATA+$0F,X
		INX
		CPX #$06
		BNE @loop4
@top:	LDX #$15		; refresh top line
@loop5:	LDA MAZEDATA-1,X
		STA $1DFF,X
		DEX
		BNE @loop5
ADDPTS:	LDY POINTS		; award points to score on screen
		BEQ CLRPTS
@loop1:	LDX DIGIT
@loop2:	LDA MAZEDATA,X
		CMP #$B9		; reach "9" ?
		BEQ @skip2
		INC MAZEDATA,X	; ding!
		DEY
		BNE @loop1
		BEQ CLRPTS
@skip2:	LDA #$B0
		STA MAZEDATA,X	; wrap to "0"
		DEX				; and increment next order
		BNE @loop2
CLRPTS:	STY POINTS
		LDX #$00
		LDY #$00
@loop6:	LDA PENALTY,X
		BNE @next		; not aware while caged
		LDA DOTS
		CMP #$A6		; make them all "smart" with 5-dots or less
		BCS @skip5
		LDA CAGEDATA,X
		BEQ @skip5		; is monster "smart"?  Red one is ...
		CMP JIFFYL		; no, so check as often as it waits
		BNE @next		; is its wait time equal to the jiffy clock?
@skip5:	LDA SPRITEX		; update this monster's awareness to where quikman is
		STA $53,Y
		LDA SPRITEY
		STA $54,Y
@next:	INY
		INY
		INX
		CPX #$04
		BNE @loop6
;
wahka:	LDA CHEWING
		BEQ @skip1
		LDA #$91		; start with an odd frequency
		STA VIC+$0C		; ignite a voice
@skip1:	LDA #$00		; dot is swallowed
		STA CHEWING
		LDA VIC+$0C
		BEQ @next1		; is this voice mute?
		LDA VIC+$0C
		AND #$01
		BEQ @skip3		; is it even?
		LDA VIC+$0C
		CLC
		ADC #$10		; increase tone
		CMP #$F1
		BCC @skip2		; is voice too high?
		SEC
		SBC #$01		; make it even
@skip2:	STA VIC+$0C
		CLC
		BCC @next1		; goto next effect
@skip3:	LDA VIC+$0C
		SEC
		SBC #$10		; drain tone
		STA VIC+$0C
@next1:	LDX CHOMP
		BEQ @skip4
		LDA JIFFYL
		AND #$01
		BNE @skip4
		LDA SNDBIT,X	; load tone data
		STA VIC+$0B
		DEC CHOMP
@skip4:	LDA EXTRAQMAN
		BNE @fini		; already got bonus life
		LDA SCORE+1
		CMP #$B1		; did quikman just score 10,000-points?
		BNE @fini
		STA EXTRAQMAN
		LDX LIVES
		LDA #$2D
		STA $1FE4,X
		LDA #$07
		STA $97E4,X
		INC LIVES		; reward
@fini:	JMP $EABF		; jump to hardware IRQ
;
; Pass A for number of jiffies to wait, while preserving X
PAUSE:	PHA
		TXA
		PHA
		JSR SPRITES		; redraw sprites
		PLA
		TAX
		PLA
		CLC
		ADC JIFFYL
@loop:	CMP JIFFYL
		BNE @loop
		RTS
;
;********************************************************************
; Maze data ($1A00 - $1BFF)
; Screen size: 24-rows by 21-columns
		.res $1A00 - *
MAZEDATA:
SCORE	= * + $06
		.byte	$93, $83, $8F, $92, $85, $BA, $B0, $B0, $B0, $B0, $B0, $B0, $A0, $A0, $A0, $B0, $B2, $B0, $B0, $B0, $B0
		.byte	$37, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3D, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $38
		.byte	$39, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $39, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $39
		.byte	$39, $1E, $37, $38, $1E, $37, $3A, $3A, $38, $1E, $39, $1E, $37, $3A, $3A, $38, $1E, $37, $38, $1E, $39
		.byte	$39, $1F, $35, $36, $1E, $35, $3A, $3A, $36, $1E, $32, $1E, $35, $3A, $3A, $36, $1E, $35, $36, $1F, $39
		.byte	$39, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $39
		.byte	$39, $1E, $33, $34, $1E, $31, $1E, $33, $3A, $3A, $3D, $3A, $3A, $34, $1E, $31, $1E, $33, $34, $1E, $39
		.byte	$39, $1E, $1E, $1E, $1E, $39, $1E, $1E, $1E, $1E, $39, $1E, $1E, $1E, $1E, $39, $1E, $1E, $1E, $1E, $39
		.byte	$35, $3A, $3A, $38, $1E, $3B, $3A, $3A, $34, $20, $32, $20, $33, $3A, $3A, $3C, $1E, $37, $3A, $3A, $36
		.byte	$20, $20, $20, $39, $1E, $39, $20, $20, $20, $20, $20, $20, $20, $20, $20, $39, $1E, $39, $20, $20, $20
		.byte	$3A, $3A, $3A, $36, $1E, $32, $20, $37, $3A, $3A, $C5, $3A, $3A, $38, $20, $32, $1E, $35, $3A, $3A, $3A
		.byte	$20, $20, $20, $20, $1E, $20, $20, $39, $20, $20, $20, $20, $20, $39, $20, $20, $1E, $20, $20, $20, $20
		.byte	$3A, $3A, $3A, $38, $1E, $31, $20, $35, $3A, $3A, $3A, $3A, $3A, $36, $20, $31, $1E, $37, $3A, $3A, $3A
		.byte	$20, $20, $20, $39, $1E, $39, $20, $20, $20, $20, $20, $20, $20, $20, $20, $39, $1E, $39, $20, $20, $20
		.byte	$37, $3A, $3A, $36, $1E, $32, $20, $33, $3A, $3A, $3D, $3A, $3A, $34, $20, $32, $1E, $35, $3A, $3A, $38
		.byte	$39, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $39, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $39
		.byte	$39, $1E, $33, $38, $1E, $33, $3A, $3A, $34, $1E, $32, $1E, $33, $3A, $3A, $34, $1E, $37, $34, $1E, $39
		.byte	$39, $1F, $1E, $39, $1E, $1E, $1E, $1E, $1E, $1E, $20, $1E, $1E, $1E, $1E, $1E, $1E, $39, $1E, $1F, $39
		.byte	$3B, $34, $1E, $32, $1E, $31, $1E, $33, $3A, $3A, $3D, $3A, $3A, $34, $1E, $31, $1E, $32, $1E, $33, $3C
		.byte	$39, $1E, $1E, $1E, $1E, $39, $1E, $1E, $1E, $1E, $39, $1E, $1E, $1E, $1E, $39, $1E, $1E, $1E, $1E, $39
		.byte	$39, $1E, $33, $3A, $3A, $3E, $3A, $3A, $34, $1E, $32, $1E, $33, $3A, $3A, $3E, $3A, $3A, $34, $1E, $39
		.byte	$39, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $1E, $39
		.byte	$35, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $3A, $36
BANNERMSG:		; ©2008 RHURST  F7=PLAY
		.byte	$3F, $B2, $B0, $B0, $B8, $A0, $92, $88, $95, $92, $93, $94, $A0, $A0, $86, $B7, $BD, $90, $8C, $81, $99
FRUITSCORE:
		.byte	$01, $03, $05, $07, $0A, $14, $1E, $32
;
;********************************************************************
; Custom character data -- must reside $1C00 - $1DFF
		.assert * = $1C00, error, "Graphics not at $1C00"
			; @ sprite #0 - quikman
QUIKMAN_GFX:
		.byte	%00111110
		.byte	%01111100
		.byte	%11111000
		.byte	%11110000
		.byte	%11110000
		.byte	%11111000
		.byte	%01111100
		.byte	%00111110
			; A
A_GFX:
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
			; B sprite #1 - red
SPRITE1_RED_GFX:
		.byte	%00111000
		.byte	%01111100
		.byte	%11111110
		.byte	%10010010
		.byte	%11111110
		.byte	%11111110
		.byte	%11111110
		.byte	%10101010
			; C
C_GFX:
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
			; D sprite #2 - green
SPRITE2_GREEN_GFX:
		.byte	%00111000
		.byte	%01111100
		.byte	%11111110
		.byte	%10010010
		.byte	%11111110
		.byte	%11111110
		.byte	%11111110
		.byte	%10101010
			; E
E_GFX:
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
			; F sprite #3 - cyan
SPRITE3_CYAN_GFX:
		.byte	%00111000
		.byte	%01111100
		.byte	%11111110
		.byte	%10010010
		.byte	%11111110
		.byte	%11111110
		.byte	%11111110
		.byte	%10101010
			; G
G_GFX:
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
			; H sprite #4 - yellow
SPRITE4_YELLOW_GFX:
		.byte	%00111000
		.byte	%01111100
		.byte	%11111110
		.byte	%10010010
		.byte	%11111110
		.byte	%11111110
		.byte	%11111110
		.byte	%10101010
			; I
I_GFX:
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000

;
;********************************************************************
; DATA
QUIKMANCLR:		; yellow
		.byte	$07
MONSTERCLR:		; red, green, cyan, yellow
		.byte	$02, $05, $03, $07
CAGEDATA:		;
		.byte	$00, $33, $76, $F9
		.byte	$02, $03, $02, $00
		.byte	$A0, $10, $00, $10, $A0, $B8, $00, $B8
FRUIT:			; cherry, strawberry, 2-peach, 2-apple, 2-pineapple, 2-tbird, 2-bell, key
		.byte	$22, $23, $24, $24, $25, $25, $26, $26, $27, $27, $28, $28, $29
FRUITCLR:		; red, red, 2-yellow, 2-red, 2-green, 2-magenta, 2-yellow, cyan
		.byte	$02, $02, $07, $07, $02, $02, $05, $05, $04, $04, $07, $07, $03
GOTEXT:			; GAME OVER
		.byte	$87, $81, $8D, $85, $A0, $8F, $96, $85, $92
INERTIA:		; maintain direction
		.byte	$01, $00, $00, $01, $FF, $00, $00, $FF
PEEKAHEAD:		;
		.byte	$01, $15
STARTPOS:		;
		.byte	$50, $88, $50, $48, $50, $58, $60, $58, $40, $58
SNDBIT:			; yummy sound effect
		.byte	$00, $00, $C0, $B8, $B0, $A8, $B0, $B8, $C0, $C8
SPRITEMASK:		; really?
		.byte	$01, $02, $04, $08, $10, $20, $40, $80
;
; Y > 0 erase; Y = 0 display
GAMEOVER:
		LDX #$08
@loop:	LDA GOTEXT,X	; GAME OVER
		CPY #$00
		BEQ @dead
		LDA #$20		; space
@dead:	STA $1F17,X		; print character
		STA $1B17,X
		LDA #$02		; red
		STA $9717,X
		DEX
		BPL @loop
		RTS
;
; A contains governor - all registers are reset to zero
SLOWDOWN:
		TAY
		TAX
@sleep:	INX
		BNE @sleep
		DEY
		BNE @sleep				; one 1000, two 1000, three 1000, ...
		TYA
		RTS
;
; resume graphic character data
		.res $1CD8 - *
			; [ explosion
EXPLOSION_GFX:
		.byte	%00000000
		.byte	%00010000
		.byte	%00010000
		.byte	%01101100
		.byte	%00010000
		.byte	%00010000
		.byte	%00000000
		.byte	%00000000
			; # smoke
SMOKE_GFX:
		.byte	%00010000
		.byte	%01000100
		.byte	%00101000
		.byte	%11000110
		.byte	%00101000
		.byte	%01000100
		.byte	%00010000
		.byte	%00000000
			; ] dust
DUST_GFX:
		.byte	%10010010
		.byte	%01000100
		.byte	%00000000
		.byte	%10000010
		.byte	%00000000
		.byte	%01000100
		.byte	%10010010
		.byte	%00000000
			; ^ dot
DOT_GFX:
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00011000
		.byte	%00011000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
			; <- powerpill (animated)
POWERPILL_ANIMATED_GFX:
		.byte	%00000000
		.byte	%00111100
		.byte	%01111110
		.byte	%01111110
		.byte	%01111110
		.byte	%01111110
		.byte	%00111100
		.byte	%00000000
			; $20 empty space
EMPTY_SPACE_GFX:
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
			; ! smiley
SMILEY_GFX:
		.byte	%00111100
		.byte	%01111110
		.byte	%10111101
		.byte	%11111111
		.byte	%10111101
		.byte	%11000011
		.byte	%01111110
		.byte	%00111100
			; " cherry
CHERRY_GFX:
		.byte	%00000100
		.byte	%00001000
		.byte	%00011000
		.byte	%00100100
		.byte	%01100010
		.byte	%11110111
		.byte	%11110010
		.byte	%01100000
			; # strawberry
STRAWBERRY_GFX:
		.byte	%00010000
		.byte	%01111100
		.byte	%11111110
		.byte	%10101010
		.byte	%11010110
		.byte	%10101010
		.byte	%01010100
		.byte	%00101000
			; $ peach
PEACH_GFX:
		.byte	%00100000
		.byte	%00010000
		.byte	%01111100
		.byte	%11111110
		.byte	%11111110
		.byte	%11111110
		.byte	%01111100
		.byte	%00111000
			; % apple
APPLE_GFX:
		.byte	%00001000
		.byte	%00010000
		.byte	%01111100
		.byte	%11111110
		.byte	%11111110
		.byte	%11111110
		.byte	%01111100
		.byte	%00101000
			; & pear
PEAR_GFX:
		.byte	%00001000
		.byte	%00010000
		.byte	%00111000
		.byte	%00111000
		.byte	%01111100
		.byte	%11111110
		.byte	%11111110
		.byte	%01101100
			; ' tbird
TBIRD_GFX:
		.byte	%00010000
		.byte	%00110000
		.byte	%10010010
		.byte	%11111110
		.byte	%01111100
		.byte	%00111000
		.byte	%00010000
		.byte	%00101000
			; ( bell
BELL_GFX:
		.byte	%00010000
		.byte	%00111000
		.byte	%01111100
		.byte	%01111100
		.byte	%01111100
		.byte	%01111100
		.byte	%11111110
		.byte	%00010000
			; ) key
KEY_GFX:
		.byte	%00011000
		.byte	%00100100
		.byte	%00011000
		.byte	%00001000
		.byte	%00001000
		.byte	%00011000
		.byte	%00001000
		.byte	%00011000
			; * pacman closed
PACMAN_CLOSED_GFX:
		.byte	%00111100
		.byte	%01111110
		.byte	%11111111
		.byte	%11111111
		.byte	%11111111
		.byte	%11111111
		.byte	%01111110
		.byte	%00111100
			; + pacman right
PACMAN_RIGHT_GFX:
		.byte	%00111110
		.byte	%01111100
		.byte	%11111000
		.byte	%11110000
		.byte	%11110000
		.byte	%11111000
		.byte	%01111100
		.byte	%00111110
			; , pacman down
PACMAN_DOWN_GFX:
		.byte	%00111100
		.byte	%01111110
		.byte	%11111111
		.byte	%11111111
		.byte	%11100111
		.byte	%11000011
		.byte	%10000001
		.byte	%00000000
			; - pacman left
PACMAN_LEFT_GFX:
		.byte	%01111100
		.byte	%00111110
		.byte	%00011111
		.byte	%00001111
		.byte	%00001111
		.byte	%00011111
		.byte	%00111110
		.byte	%01111100
			; . pacman up
PACMAN_UP_GFX:
		.byte	%00000000
		.byte	%10000001
		.byte	%11000011
		.byte	%11100111
		.byte	%11111111
		.byte	%11111111
		.byte	%01111110
		.byte	%00111100
			; / ghost chasing
GHOST_CHASING_GFX:
		.byte	%00111000
		.byte	%01111100
		.byte	%11111110
		.byte	%10010010
		.byte	%11111110
		.byte	%11111110
		.byte	%11111110
		.byte	%10101010
			; 0 ghost fleeing
GHOST_FLEEING_GFX:
		.byte	%00111000
		.byte	%01111100
		.byte	%11111110
		.byte	%10010010
		.byte	%11111110
		.byte	%10000010
		.byte	%11111110
		.byte	%01010100
			; 1 maze wall north
MAZE_WALL_NORTH_GFX:
		.byte	%00000000
		.byte	%00011000
		.byte	%00100100
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
			; 2 maze wall south
MAZE_WALL_SOUTH_GFX:
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%00100100
		.byte	%00011000
		.byte	%00000000
			; 3 maze wall west
MAZE_WALL_WEST_GFX:
		.byte	%00000000
		.byte	%00011111
		.byte	%00100000
		.byte	%01000000
		.byte	%01000000
		.byte	%00100000
		.byte	%00011111
		.byte	%00000000
			; 4 maze wall east
MAZE_WALL_EAST_GFX:
		.byte	%00000000
		.byte	%11111000
		.byte	%00000100
		.byte	%00000010
		.byte	%00000010
		.byte	%00000100
		.byte	%11111000
		.byte	%00000000
			; 5 maze wall s-w elbow
MAZE_WALL_SW_ELBOW_GFX:
		.byte	%01000010
		.byte	%01000001
		.byte	%01000000
		.byte	%01000000
		.byte	%01000000
		.byte	%00100000
		.byte	%00011111
		.byte	%00000000
			; 6 maze wall s-e elbow
MAZE_WALL_SE_ELBOW_GFX:
		.byte	%01000010
		.byte	%10000010
		.byte	%00000010
		.byte	%00000010
		.byte	%00000010
		.byte	%00000100
		.byte	%11111000
		.byte	%00000000
			; 7 maze wall n-w elbow
MAZE_WALL_NW_ELBOW_GFX:
		.byte	%00000000
		.byte	%00011111
		.byte	%00100000
		.byte	%01000000
		.byte	%01000000
		.byte	%01000000
		.byte	%01000001
		.byte	%01000010
			; 8 maze wall n-e elbow
MAZE_WALL_NE_ELBOW_GFX:
		.byte	%00000000
		.byte	%11111000
		.byte	%00000100
		.byte	%00000010
		.byte	%00000010
		.byte	%00000010
		.byte	%10000010
		.byte	%01000010
			; 9 maze wall vertical
MAZE_WALL_VERTICAL_GFX:
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
		.byte	%01000010
			; : maze wall horizontal
MAZE_WALL_HORIZONTAL_GFX:
		.byte	%00000000
		.byte	%11111111
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%11111111
		.byte	%00000000
			; ; maze wall west tee
MAZE_WALL_WEST_TEE_GFX:
		.byte	%01000010
		.byte	%01000001
		.byte	%01000000
		.byte	%01000000
		.byte	%01000000
		.byte	%01000000
		.byte	%01000001
		.byte	%01000010
			; < maze wall east tee
MAZE_WALL_EAST_TEE_GFX:
		.byte	%01000010
		.byte	%10000010
		.byte	%00000010
		.byte	%00000010
		.byte	%00000010
		.byte	%00000010
		.byte	%10000010
		.byte	%01000010
			; = maze wall north tee
MAZE_WALL_NORTH_TEE_GFX:
		.byte	%00000000
		.byte	%11111111
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%10000001
		.byte	%01000010
			; > maze wall south tee
MAZE_WALL_SOUTH_TEE_GFX:
		.byte	%01000010
		.byte	%10000001
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%00000000
		.byte	%11111111
		.byte	%00000000
			; (C)copyright symbol
COPYRIGHT_SYMBOL_GFX:
		.byte	%00111100
		.byte	%01000010
		.byte	%10011001
		.byte	%10100001
		.byte	%10100001
		.byte	%10011001
		.byte	%01000010
		.byte	%00111100

