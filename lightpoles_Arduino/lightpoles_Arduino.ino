/********************************************************************************
 * 24 April 2012
 * uses ShiftPWM library
 * receives Processing-generated RGBLED info and sends out to poles via 74hc595s
 * 
 * pin       arduino   74hc595
 * latch     8         12
 * data      11        15
 * clock     13        11
 * 
 * changes:
 * - CORRECTLY receives full pole array (moved color++ inside brackets)
 ********************************************************************************/

#include <SPI.h>
const int ShiftPWM_latchPin=8;
const bool ShiftPWM_invertOutputs = 0;
#include <ShiftPWM.h>   // include ShiftPWM.h after setting the pins!
unsigned char maxBrightness = 255;
unsigned char pwmFrequency = 75;
byte incoming = 0;
byte message = 0;
byte LED = 0;
byte color = 0;
int REGISTER_COUNT = 6;
int poleArray[16][3]; //THIS MUST BE CHANGED WHEN CHANGING REGISTER_COUNT. ARDUINO DOES NOT LIKE ARRAYS DEFINED WITH VARIABLES - [light number][R,G,B values]

void setup() {
  pinMode(ShiftPWM_latchPin, OUTPUT);
  SPI.setBitOrder(LSBFIRST);
  SPI.setClockDivider(SPI_CLOCK_DIV4);
  SPI.begin();
  ShiftPWM.SetAmountOfRegisters(REGISTER_COUNT);
  ShiftPWM.Start(pwmFrequency,maxBrightness);
  ShiftPWM.SetAll(0);
  Serial.begin(115200);
  //initialize array
  for (int i=0 ; i<REGISTER_COUNT*8/3 ; i++) {
    for (int j=0 ; j<3 ; j++) {
      poleArray[i][j]=0;
    }
  }
}

void loop() {
  if (Serial.available() > 0) {
    incoming = Serial.read();
    if (incoming == 255) {
      //message = incoming;
    } else {
      poleArray[LED][color] = incoming;
      if (poleArray[LED][color] == 254) {
        poleArray[LED][color] = 255;
      }
      color++;
    }
    if (color > 2) {
      color = 0;
      LED++;
    }
    if (LED == REGISTER_COUNT*8/3) {
      for (int i=0 ; i<REGISTER_COUNT*8/3 ; i++) {
        ShiftPWM.SetGroupOf3(i, poleArray[i][0], poleArray[i][1], poleArray[i][2]);
        //println(i + "-- R: " poleArray[i][0] + " G: " poleArray[i][1] + " B: " poleArray[i][2]);
      }
      color = 0;
      LED = 0;
    }
  }
}
