declare options "[midi:on][nvoices:16]";
import("stdfaust.lib");

import("spulse.lib");
import("stereoizer.lib");
import("akjrev_48000.lib");

gate         = button("v:midi/[0]gate[hidden:1]");
gain         = hslider("v:midi/[1]gain[hidden:1]",0.1,0,1,0.01);
mkey         = hslider("v:midi/[2]key[hidden:1]",60,36,96,1);
stereo_width = hslider("[4]stereo_width[midi:ctrl 41]", 1.0, 0, 1, 0.007874);
master_vol   = hslider("[5]master_vol  [midi:ctrl 48]", 0.13, 0, 1, 0.007874);

freq = midikey2hz(mkey-36)
with {
    ///////////////////////////////////////////////////////////////////////////
    // johnson-secor_rwt.scl (Johnson/Secor Rational Well-Temperment with    //
    // five 24/19 major thirds)                                              //
    //                                                                       //
    // It's laid out here in a 4-octave keyboard setup, perfect for a little //
    // 49-key controller to simulate a 'clav' sound with an authentic        //
    // range/gamut. As a result, MIDI key #36 should map to index 0 in the   //
    // tables below. This is why we subtract 36 in the 'mkey' declarations.  //
    ///////////////////////////////////////////////////////////////////////////
    myhzvals = waveform{
        65.25,
        68.875,
        73.08402777777777715,
        77.3333333333333286,
        81.7890625,
        87,
        91.8333333333333286,
        97.6484375,
        103.3125,
        109.3390624999999972,
        116,
        122.4444444444444429,
        130.5,
        137.75,
        146.1680555555555543,
        154.6666666666666572,
        163.578125,
        174,
        183.6666666666666572,
        195.296875,
        206.625,
        218.6781249999999943,
        232,
        244.8888888888888857,
        261,
        275.5,
        292.3361111111111086,
        309.3333333333333144,
        327.15625,
        348,
        367.3333333333333144,
        390.59375,
        413.25,
        437.3562499999999886,
        464,
        489.7777777777777715,
        522,
        551,
        584.6722222222222172,
        618.6666666666666288,
        654.3125,
        696,
        734.6666666666666288,
        781.1875,
        826.5,
        874.7124999999999773,
        928,
        979.5555555555555429,
        1044
    };
    midikey2hz(mk) = myhzvals,int(mk) : rdtable;
};

adj_cf = midikey2cf(mkey-36)
with {
    mycfs = waveform {
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        1,1,1,1,1,1,1,1,1,1,1,1,
        0.6,    // C5
        0.6,    // Db5
        0.9,    // D5
        0.8,    // Eb5
        1,      // E5
        0.6,    // F5
        1,      // F#5
        1,      // G5
        0.5,    // G#5
        0.6,    // A5
        0.8,    // Bb5
        0.6,    // B5
        0.5     // C6
    };
    midikey2cf(mk) = mycfs,int(mk) : rdtable;
};

///////////////////////////////////////////////////////////////////////////////
// Basic params!                                                             //
//                                                                           //
// You will notice that the older version had nine dials, and this has now   //
// been reduced to just a master volume, basically, b/c I wanted to find     //
// ideal settings, and then "set it and forget it". A factor contributing to //
// parameter reduction was that I went back to a more basic design with the  //
// following ideas in mind:                                                  //
//                                                                           //
//    * No additional vco wave, just pink noise in the excitation            //
//    * Bringing a filter back into the main resonator feedback. This gives  //
//      a more "naturalistic" decay character, as it corresponds to hi-freq  //
//      energy loss in a string model, and allows me not to have need for a  //
//      secondary post-string-model filter to gain back naturalism.          //
//    * As mentioned, after empirical experimentation, lock in values, in so //
//      doing, reducing the need for a dial to tweak to get a good sound.    //
//                                                                           //
// I wanted the lowest note to ring for ~10 seconds, and the hightest for    //
// just about ~3-4 seconds. This suited the music and wasn't really based on //
// looking to precisely emulated a real clavichord. In addition, I wanted to //
// have the ring of the note be a certain brightness that sounded good while //
// also staying within those time contraints. And brightness and decay being //
// related, this meant bringing a "sustain" parameter to assist the decay    //
// to be slightly faster, because the slightly brighter sound I wanted would //
// naturally ring a bit longer otherwise...                                  //
///////////////////////////////////////////////////////////////////////////////
bright_C1    = 89;     // not magic, emprically getting appropriate brightness and decay (was 97)
bright_C5    = 69;     // same thing  (was 73)
sustain      = 0.9985; // adjustment that allows note to stay bright but decay a bit faster
/////////////////////////////////////////
// The Superclav instrument definition //
/////////////////////////////////////////
superclav = excitation : fi.highpass(2,35) : resonator(delsmps)*env*master_vol*0.5 : adj_flt
            <: stereoizer(stereo_width)
with {
    //////////////////////////////////////////////////////////
    // Convert desired voice frequency to number of samples //
    //                                                      //
    // Think of this as frequency -> string (delay) length  //
    //////////////////////////////////////////////////////////
    delsmps        = ma.SR/freq;
    /////////////////////////////////////////////////////////////
    // Envelope params, used by excition and wrapping envelope //
    /////////////////////////////////////////////////////////////
    attack_numer   = 0.0125+(mkey-36)*(0.025/48);             // kbd tracking
    attack         = (attack_numer/freq)*0.25;
    exc_rel        = attack;
    release        = attack*6;
    ///////////////////////////
    // Pink-noise excitation //
    ///////////////////////////
    exc_factor     = 1/(2.0+(mkey-36)*(-1/48));               // kbd tracking
    exc_col_noi    = -1/2;                                    // -1/2 is pink noise
    exc_window     = spulse(int(delsmps*exc_factor+0.5),gate);
    exc_env        = en.are(attack,exc_rel,gate);
    base_gain      = ((pow(gain,1.666)*0.875)+0.125)*0.8;     // keep gain > 0.125 to reduce stray weak hits
    gain_comp      = (mkey>=72)*(mkey-72)*(0.1/12.0);
    adj_gain       = base_gain+gain_comp;
    exc_filt       = *(adj_gain) : + ~ *(1-adj_gain);         // filter for velocity response
    impulse_factor = (mkey-36)*(0.59/48);                     // was (0.37/48) then (0.53/48)
    impulse        = gate*adj_gain*impulse_factor : ba.impulsify;
    excitation     = (no.colored_noise(8,exc_col_noi) + impulse) * (adj_gain*exc_env*exc_window) : exc_filt;
    /////////////////////////////////////
    // Resonator filter and its params //
    /////////////////////////////////////
    brightness     = bright_C1+(bright_C5-bright_C1)*((mkey-36)*(1/48));
    tau            = 1/((freq*4*ma.PI)+(freq*brightness*adj_gain*2*ma.PI));
    pole_val       = ba.tau2pole(tau);
    flt            = *(1-pole_val) : + ~ *(pole_val);   // standard 1-pole lowpass equation
    ///////////////////////////////////////
    // The actual string model resonator //
    ///////////////////////////////////////
    resonator(ds)  = (+ : de.fdelay2(4096, ds-1)) ~ (flt*sustain) : fi.dcblocker;
    ////////////////////////////////////////////////////////////
    // Wrap it all in an anti-click and MIDI-playing envelope //
    ////////////////////////////////////////////////////////////
    env            = en.adsre(attack*0.5,0,1,release,gate); // N.B. added the *0.5 on 2025-04-20
    ////////////////////////////////////
    // Outer ping compensation filter //
    ////////////////////////////////////
    adj_flt        = *(adj_cf) : + ~ *(1-adj_cf);
};

process = superclav;
effect  = akjrev_demo;
