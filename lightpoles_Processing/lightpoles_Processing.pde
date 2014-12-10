/**************************************************************************
 * 24 April 2012
 * Input: MIDI, OSC, or audio
 * Output: to Arduino via serial
 *
 * changes:
 * - properly working MIDI
 * to do:
 * - fix indexing reversal on display (display and pole y values are opposite, pole is correct)
 * - implement fades on MIDI
 * - clean up terrible overuse of variables
 * - create separate selectable color creation functions
 * - beat detection?
 **************************************************************************/

import ddf.minim.AudioPlayer;
import ddf.minim.AudioInput;
import ddf.minim.AudioOutput;
import ddf.minim.Minim;
import ddf.minim.analysis.FFT;
import rwmidi.*;
import processing.serial.*;
import controlP5.*;
import oscP5.*;
import netP5.*;

//Constants
int POLE_COUNT = 8;
int LIGHTS_PER_POLE = 16;

int SAMPLE_BUFFER = 1024; //1024
int LOWEST_HZ = 55; //55
int BANDS_PER_OCTAVE = 12; //12

int FADE_MAX = 2000;
int FULL_BRIGHT_THRESHOLD[] = new int[] { 
  1000, 1000
}; //default = 3000
int FULL_SATURATION_THRESHOLD = 20; //default = 1
int SATURATION_OFFSET = 20; //20

int DISPLAY_PIXEL_WIDTH=20; //16
int DISPLAY_PIXEL_X=180; //120
int DISPLAY_PIXEL_Y=80; //20
int KNOB_SIZE = 60;
int CONTROL_PIXEL_X=90-(KNOB_SIZE/2); //120
int CONTROL_PIXEL_Y=100; //20

int FADE_INTENSITY = 1; //default = 1
int RANDOM_INTENSITY = 40; //default = 40

int FILTER_MAX = 200;
int POLE_FILTER_INCREMENT[] = new int[] { 
  100, 100
}; //default = 75
float C = 32.7031956625748;


//Globals
PImage lightModel = createImage(POLE_COUNT, LIGHTS_PER_POLE, RGB);
PImage fftImage = createImage(POLE_COUNT, LIGHTS_PER_POLE, HSB);
String [] noteStrings = new String[] {
  "F#", "G", "G#", "A", "A#", "B", "C", "C#", "D", "D#", "E", "F"
};
float [][] volumePoleFilter = new float[POLE_COUNT][LIGHTS_PER_POLE];
int poleArray[][] = new int[POLE_COUNT*LIGHTS_PER_POLE][3];
int mode = 0;
float oldCheck = 0;
boolean MIDIhue=true;
float H=0;
float S=1;  //saturation (constant)
float L=0;

MidiInput MIDIin;
MidiOutput MIDIout;
Minim minim;
AudioInput audio;
//AudioPlayer audio;
FFT fft;
//Serial port1, port2;
ControlP5 controlP5;
Knob fadeL, fadeR, filterL, filterR;
OscP5 oscP5;
NetAddress oscController;
String galaxyNexus = "192.168.1.40";
//================================================================================
//==============================BEGIN FUNCTIONS===================================
//================================================================================
void setup() {
  size(400, 600);
  smooth();
  //port1 = new Serial(this, Serial.list()[0], 115200);
  //port2 = new Serial(this, Serial.list()[2], 115200);
  minim = new Minim(this);
  controlP5 = new ControlP5(this);
  controlP5.tab("default").setLabel("global");
  fadeL = controlP5.addKnob("fadeL", FADE_MAX, 1, FULL_BRIGHT_THRESHOLD[0], CONTROL_PIXEL_X, CONTROL_PIXEL_Y, KNOB_SIZE);
  fadeR = controlP5.addKnob("fadeR", FADE_MAX, 1, FULL_BRIGHT_THRESHOLD[1], CONTROL_PIXEL_X+220, CONTROL_PIXEL_Y, KNOB_SIZE);
  filterL = controlP5.addKnob("filterL", FILTER_MAX, 1, POLE_FILTER_INCREMENT[0], CONTROL_PIXEL_X, CONTROL_PIXEL_Y+120, KNOB_SIZE);
  filterR = controlP5.addKnob("filterR", FILTER_MAX, 1, POLE_FILTER_INCREMENT[1], CONTROL_PIXEL_X+220, CONTROL_PIXEL_Y+120, KNOB_SIZE);
  controlP5.addToggle("hue")
     .setPosition(160,460)
     .setSize(80,20)
     .setValue(true)
     .setMode(ControlP5.SWITCH)
     ;
  controlP5.controller("fadeL").moveTo("global");
  controlP5.controller("fadeR").moveTo("global");
  controlP5.controller("filterL").moveTo("global");  
  controlP5.controller("filterR").moveTo("global");
  controlP5.controller("hue").moveTo("MIDI");
  controlP5.tab("default").activateEvent(true);
  controlP5.tab("default").setId(0);
  controlP5.tab("input").activateEvent(true);
  controlP5.tab("input").setId(1);
  controlP5.tab("MIDI").activateEvent(true);
  controlP5.tab("MIDI").setId(2);
  oscP5 = new OscP5(this, 8000);
  oscController = new NetAddress(galaxyNexus, 9000);
  MIDIin = RWMidi.getInputDevices()[0].createInput(this);
  MIDIout = RWMidi.getOutputDevices()[0].createOutput();
  MidiInputDevice devices[] = RWMidi.getInputDevices(); 
  for (int i = 0; i < devices.length; i++) { 
    println(i + ": " + devices[i].getName());
  }
  wipeControls();
  wipeDisplay();
}
//================================================================================
//get rid of this bullshit
void hue(boolean flag) {
  if (flag == true) MIDIhue=true;
  else MIDIhue=false;
}
//================================================================================
void draw() {
  ///*
  //setup filter so the lights will pulse from the center
  for (int i=0;i<(LIGHTS_PER_POLE/2);i++) {
    volumePoleFilter[0][i] = ((LIGHTS_PER_POLE/2)-i) * POLE_FILTER_INCREMENT[0];
    volumePoleFilter[0][(LIGHTS_PER_POLE-1)-i] = volumePoleFilter[0][i];
    volumePoleFilter[1][i] = ((LIGHTS_PER_POLE/2)-i) * POLE_FILTER_INCREMENT[1];
    volumePoleFilter[1][(LIGHTS_PER_POLE-1)-i] = volumePoleFilter[1][i];
  }
  background(0);
  if (mode == 0) {
    blendy();
    display();
    toArduino();
  } else if (mode == 1) {
    fft.forward(audio.left);
    doFFT(0);
    fft.forward(audio.right);
    doFFT(1);
    drawRandom();
    //fadeToBlack();
    blendy();
    display();
    //float check = red(lightModel.pixels[7]) + red(lightModel.pixels[23]) + green(lightModel.pixels[7]) + green(lightModel.pixels[23]) + blue(lightModel.pixels[7]) + blue(lightModel.pixels[23]);
    //if (check != oldCheck) {
      toArduino();
    //}
    //oldCheck = check;
  } else if (mode == 2) {
    display();
    toArduino();
  }
  //*/
}  
//================================================================================
void wipeControls() {
  OscMessage onerotary2 = new OscMessage("/1/rotary2");
  onerotary2.add(.5);
  oscP5.send(onerotary2, oscController);
  OscMessage onerotary3 = new OscMessage("/1/rotary3");
  onerotary3.add(.5);
  oscP5.send(onerotary3, oscController);
  OscMessage onerotary5 = new OscMessage("/1/rotary5");
  onerotary5.add(.5);
  oscP5.send(onerotary5, oscController);
  OscMessage onerotary6 = new OscMessage("/1/rotary6");
  onerotary6.add(.5);
  oscP5.send(onerotary6, oscController);
}

void wipeDisplay() {
  println("wiping...");
  for(int i=0 ; i<POLE_COUNT*LIGHTS_PER_POLE ; i++) {
    fftImage.pixels[i] = color(0);
  }
  blendy();
  display();
}
//================================================================================
void doFFT(int k) {
  //HSB for pole, note = hue, s = percentage of the note's band vs the total, b = total
  stroke(255);
  noFill();
  rectMode(CORNERS);
  //do left, then right
  int w = int(512/fft.avgSize()*3/4);
  int[] noteTotals = new int[BANDS_PER_OCTAVE];
  float highestNoteValue = 0;
  int highestNote = 0;
  float totalValue = 1;
  ///*
  int highest = 0;
  for (int i = 0; i < fft.specSize(); i++) {
    if (fft.getBand(i)>fft.getBand(highest)) highest=i;
  }
  float freq = highest / float(audio.bufferSize()) * audio.sampleRate();
  float pitch = (69 + 12 * (log(freq/440.0) / log(2.0)));
  //float remainder = pitch - int(pitch);
  pitch = round(pitch);
  freq = int(freq);
  int octave = int(pitch) / 12 - 2;
  //println("f: " + freq + " p: " + pitch + " o: " + octave);
  //*/
  for (int i = 0; i < fft.avgSize(); i++) {
    float currentAvg = fft.getAvg(i);
    int currentNote = i%BANDS_PER_OCTAVE;
    totalValue+=currentAvg;
    // draw spectrum - clean this up
    if (k==0) {
      rect(DISPLAY_PIXEL_X-DISPLAY_PIXEL_WIDTH, DISPLAY_PIXEL_Y+DISPLAY_PIXEL_WIDTH*(LIGHTS_PER_POLE)-i*w, DISPLAY_PIXEL_X-DISPLAY_PIXEL_WIDTH-currentAvg, DISPLAY_PIXEL_Y+DISPLAY_PIXEL_WIDTH*(LIGHTS_PER_POLE)-i*w-w);
    } else if (k==1) {
      rect(DISPLAY_PIXEL_X+DISPLAY_PIXEL_WIDTH*3, DISPLAY_PIXEL_Y+DISPLAY_PIXEL_WIDTH*(LIGHTS_PER_POLE)-i*w, DISPLAY_PIXEL_X+DISPLAY_PIXEL_WIDTH*3+currentAvg, DISPLAY_PIXEL_Y+DISPLAY_PIXEL_WIDTH*(LIGHTS_PER_POLE)-i*w-w);
    }
    // sum bands and record band with highest value
    noteTotals[currentNote] += currentAvg;
    if (noteTotals[currentNote] > highestNoteValue) {
      highestNoteValue = noteTotals[currentNote];
      highestNote = currentNote;
    }
  }
  text(noteStrings[highestNote], DISPLAY_PIXEL_X+(k*DISPLAY_PIXEL_WIDTH), DISPLAY_PIXEL_Y-20);
  float H = (freq-C*pow(2, octave))/(C*pow(2, octave));
  float S = min(((highestNoteValue/totalValue)*FULL_SATURATION_THRESHOLD)+SATURATION_OFFSET, FULL_SATURATION_THRESHOLD);
  setColor(H, S, totalValue, k);
}
//================================================================================
void drawRandom() {
  for (int i=0;i<RANDOM_INTENSITY;i++) {
    lightModel.pixels[(floor(random(LIGHTS_PER_POLE))*POLE_COUNT)+floor(random(POLE_COUNT))] = color(255, 255, 255);
  }
}
//================================================================================
void fadeToBlack() {
  for (int i= 0;i<(POLE_COUNT*LIGHTS_PER_POLE);i++) {
    float r = max(0, red(lightModel.pixels[i])-FADE_INTENSITY);
    float g = max(0, green(lightModel.pixels[i])-FADE_INTENSITY);
    float b = max(0, blue(lightModel.pixels[i])-FADE_INTENSITY);
    lightModel.pixels[i] = color(r, g, b);
  }
}
//================================================================================
void blendy() {
  lightModel.blend(fftImage, 0, 0, POLE_COUNT, LIGHTS_PER_POLE, 0, 0, POLE_COUNT, LIGHTS_PER_POLE, BLEND);
}
//================================================================================
void display() {
  stroke(#FFCC00);
  rectMode(CORNER);
  for (int x = 0; x < POLE_COUNT; x++) {
    for (int y = 0; y < LIGHTS_PER_POLE; y++ ) {
      fill(color(lightModel.pixels[(x*LIGHTS_PER_POLE)+y]));
      rect((x*DISPLAY_PIXEL_WIDTH)+DISPLAY_PIXEL_X, (y*DISPLAY_PIXEL_WIDTH)+DISPLAY_PIXEL_Y, DISPLAY_PIXEL_WIDTH, DISPLAY_PIXEL_WIDTH);
      //println("y: " + y + " x: " + x);
    }
  }
}
//================================================================================
void setColor(float H, float S, float total, int k) {
  colorMode(HSB, 1, FULL_SATURATION_THRESHOLD, FULL_BRIGHT_THRESHOLD[k]);
  for (int x=k ; x<k+1 ; x++) { //changed
    for (int y=0 ; y<LIGHTS_PER_POLE ; y++ ) {
      float B = max(0, min(total-volumePoleFilter[k][y], FULL_BRIGHT_THRESHOLD[k]));
      //println("H: " + H + " S: " + S + " B: " + B);
      fftImage.pixels[(x*LIGHTS_PER_POLE)+y] = color(H, S, B);
      //println((x*LIGHTS_PER_POLE)+y + ": " + y);
    }
  }
  colorMode(RGB, 256);
}
//==========================================================================================
void controlEvent(ControlEvent theControlEvent) {
  if (theControlEvent.isController()) {
    //println("controller : "+theControlEvent.controller().id() + " name: " +theControlEvent.controller().name());
  } else if (theControlEvent.isTab()) {
    wipeDisplay();
    if ((theControlEvent.tab().id() == 1) && (mode != 1)) {
      audio = minim.getLineIn(Minim.STEREO, SAMPLE_BUFFER);
      //audio = minim.loadFile("sample.mp3", SAMPLE_BUFFER);
      //audio.loop();
      fft = new FFT(audio.bufferSize(), audio.sampleRate());
      fft.logAverages(LOWEST_HZ, BANDS_PER_OCTAVE);
      fft.window(FFT.HAMMING);
    } else if ((theControlEvent.tab().id() != 1) && (mode == 1)) {
      audio.close();
      minim.stop();
    }
    mode = theControlEvent.tab().id();
  }
}
//================================================================================
void fadeL(int val) {
  FULL_BRIGHT_THRESHOLD[0] = val;
  OscMessage oscMessage = new OscMessage("/1/rotary2");
  oscMessage.add(1-(float(val)/2000));
  oscP5.send(oscMessage, oscController);
}
void fadeR(int val) {
  FULL_BRIGHT_THRESHOLD[1] = val;
  OscMessage oscMessage = new OscMessage("/1/rotary5");
  oscMessage.add(1-(float(val)/2000));
  oscP5.send(oscMessage, oscController);
}
void filterL(int val) {
  POLE_FILTER_INCREMENT[0] = val;
  OscMessage oscMessage = new OscMessage("/1/rotary3");
  oscMessage.add(1-(float(val)/200));
  oscP5.send(oscMessage, oscController);
}
void filterR(int val) {
  POLE_FILTER_INCREMENT[1] = val;
  OscMessage oscMessage = new OscMessage("/1/rotary6");
  oscMessage.add(1-(float(val)/200));
  oscP5.send(oscMessage, oscController);
}
//==========================================================================================
void oscEvent(OscMessage theOscMessage) {
  ///*
  //println("### received an osc message. addrpattern: "+theOscMessage.addrPattern() + " typetag: "+theOscMessage.typetag());
  if ((theOscMessage.addrPattern().equals("/1")) || (theOscMessage.addrPattern().equals("/2")) || (theOscMessage.addrPattern().equals("/3"))) {
    //catch tab changes
  } else if ((theOscMessage.addrPattern().equals("/3/xy1")) || (theOscMessage.addrPattern().equals("/3/xy2"))) {
    if (theOscMessage.addrPattern().equals("/3/xy1")) {
      int k=0;
      colorMode(HSB, 1, FULL_SATURATION_THRESHOLD, FULL_BRIGHT_THRESHOLD[k]);
      float H = theOscMessage.get(1).floatValue();
      float total = theOscMessage.get(0).floatValue()*FULL_BRIGHT_THRESHOLD[k];
      println("H: " + H + " B: " + total);
      float S = FULL_SATURATION_THRESHOLD;
      for (int x=k ; x<k+1 ; x++) { //changed
        for (int y=0 ; y<LIGHTS_PER_POLE ; y++) {
          float B = max(0, min(total-volumePoleFilter[k][y], FULL_BRIGHT_THRESHOLD[k]));
          fftImage.pixels[(x*LIGHTS_PER_POLE)+y] = color(H, S, B);
        }
      }
      colorMode(RGB, 256);
    } else if (theOscMessage.addrPattern().equals("/3/xy2")) {
      int k=1;
      colorMode(HSB, 1, FULL_SATURATION_THRESHOLD, FULL_BRIGHT_THRESHOLD[k]);
      float H = theOscMessage.get(1).floatValue();
      float total = theOscMessage.get(0).floatValue()*FULL_BRIGHT_THRESHOLD[k];
      println("H: " + H + " B: " + total);
      float S = FULL_SATURATION_THRESHOLD;
      for (int x=k ; x<k+1 ; x++) { //changed
        for (int y=0 ; y<LIGHTS_PER_POLE ; y++) {
          float B = max(0, min(total-volumePoleFilter[k][y], FULL_BRIGHT_THRESHOLD[k]));
          fftImage.pixels[(x*LIGHTS_PER_POLE)+y] = color(H, S, B);
        }
      }
      colorMode(RGB, 256);
    }
  } else {
    float OSCvalue = (1-theOscMessage.get(0).floatValue());
    if (OSCvalue == 0) OSCvalue = 0.001;
    if (theOscMessage.addrPattern().equals("/1/rotary1")) {
      //nothing yet
    }
    if (theOscMessage.addrPattern().equals("/1/rotary2")) {
      FULL_BRIGHT_THRESHOLD[0] = int(FADE_MAX*OSCvalue);
      fadeL.setValue(FULL_BRIGHT_THRESHOLD[0]);
    }
    if (theOscMessage.addrPattern().equals("/1/rotary3")) {
      POLE_FILTER_INCREMENT[0] = int(FILTER_MAX*OSCvalue);
      filterL.setValue(POLE_FILTER_INCREMENT[0]);
    }
    if (theOscMessage.addrPattern().equals("/1/rotary4")) {
      //nothing yet
    }
    if (theOscMessage.addrPattern().equals("/1/rotary5")) {
      FULL_BRIGHT_THRESHOLD[1] = int(FADE_MAX*OSCvalue);
      fadeR.setValue(FULL_BRIGHT_THRESHOLD[1]);
    }
    if (theOscMessage.addrPattern().equals("/1/rotary6")) {
      POLE_FILTER_INCREMENT[1] = int(FILTER_MAX*OSCvalue);
      filterR.setValue(POLE_FILTER_INCREMENT[1]);
    }
  }
}

//================================================================================
void noteOnReceived(Note n) {  //figure out LED number, modify color, and draw LED
  if (mode==2) {
    int note = n.getPitch()%(POLE_COUNT*16);
    if (MIDIhue==true) {
      H = n.getVelocity()/127;
      L=0.5;
    } else {
      L = float(n.getVelocity())/127;
    }
    defColor(note);
  }
}
//================================================================================
void noteOffReceived(Note n) {  //figure out LED number and turn it off
  if (mode==2) {
    int note = n.getPitch()%(POLE_COUNT*16);
    lightModel.pixels[note] = color(0,0,0);
  }
}

/*
  if (mode==1) {
    int note = n.getPitch();
    if (n.getChannel() == 0) {
      L = 0;
      defColor();
      toGrid(note, R, G, B);
      toArduino(note, R, G, B);
    }
    else if (n.getChannel() == 1) { // PWM lights; fadeout is dependent on subracting from L value. this may only be practical if hus is determined by velocity [not modulaion]
      fadeStatus[note] = true;
    }
  }
}
*/
//================================================================================
void controllerChangeReceived(rwmidi.Controller contr) {  //controller change of 1 is modulation, corresponds to hue control
  if (mode==2) {
    if ((contr.getCC() == 1) && (MIDIhue == false)) {
      H=float(contr.getValue())/127*360;
      //if (indiv == false) {
        //make the colors change when modulation changes - not implemented yet
      //}
    }
  }
}
//================================================================================
void defColor(int note) {  //algorithm to convert HSL to RGB - uses ints rather than floats, so it must be scaled up
  //println("H: " + H + " S: " + S + " L: " + L);
  float R=0;
  float G=0;
  float B=0;
  float Lprime=2*L-1;   //calculate chroma
  Lprime=abs(Lprime);
  float C=(1-Lprime)*S; //chroma [largest component]
  float Hprime=H/60;   //then calculate 2nd largest component
  float Hprime2=Hprime%2-1;
  Hprime2=abs(Hprime2);
  float X=C*(1-Hprime2); //2nd largest component
  if ((Hprime < 0) || (Hprime > 6)) {   //based on Hprime, set hue for each color
    R=0;
    G=0;
    B=0;
  }
  if ((Hprime >= 0) && (Hprime < 1)) {
    R=C;
    G=X;
    B=0;
  }
  if ((Hprime >= 1) && (Hprime < 2)) {
    R=X;
    G=C;
    B=0;
  }
  if ((Hprime >= 2) && (Hprime < 3)) {
    R=0;
    G=C;
    B=X;
  }
  if ((Hprime >= 3) && (Hprime < 4)) {
    R=0;
    G=X;
    B=C;
  }
  if ((Hprime >= 4) && (Hprime < 5)) {
    R=X;
    G=0;
    B=C;
  }
  if ((Hprime >= 5) && (Hprime <= 6)) {
    R=C;
    G=0;
    B=X;
  }
  float m=L-(C/2);   //finally, add lightness factor and scale up for eventual analogWrite
  R=(R+m)*255;
  G=(G+m)*255;
  B=(B+m)*255;
  //println("l: " + note + " R: " + R + " G: " + G + " B: " + B);
  lightModel.pixels[note] = color(int(R),int(G),int(B));
}
//================================================================================
void toArduino() {
  //port1.write(255);
  //port2.write(255);
  for (int i=0 ; i<POLE_COUNT*LIGHTS_PER_POLE ; i++) { 
    poleArray[i][0] = int(red(color(lightModel.pixels[i])));
    poleArray[i][1] = int(green(color(lightModel.pixels[i])));
    poleArray[i][2] = int(blue(color(lightModel.pixels[i])));
    //println(i+ ": " + poleArray[i][0] + " : " + poleArray[i][1] + " : " + poleArray[i][2]);
    for (int j=0 ; j<3 ; j++) {
      if ((poleArray[i][j] == 255) || (poleArray[i][j] == 1)) {
        poleArray[i][j] = poleArray[i][j]-1;
      }
      if (i < LIGHTS_PER_POLE) {
        //port1.write(poleArray[i][j]);
        fill(poleArray[i][0], poleArray[i][1], poleArray[i][2]);
      } else {
        //port2.write(poleArray[i][j]);
      }
    }
  }
}

