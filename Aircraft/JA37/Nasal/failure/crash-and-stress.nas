#
# A Flightgear crash and stress damage system.
#
# Inspired and developed from the crash system in Mig15 by Slavutinsky Victor. And by the late Hal V. Engel's formula for wingload stress.
#
# Authors: Slavutinsky Victor, Nikolai V. Chr. (Necolatis)
#
#
# Version 0.19
#
# License:
#   GPL 2.0


var TRUE = 1;
var FALSE = 0;

var CrashAndStress = {
	# pattern singleton
	_instance: nil,
	# Get the instance
	new: func (gears, stressLimit = nil, wingsFailureModes = nil) {

		var m = nil;
		if(me._instance == nil) {
			me._instance = {};
			me._instance["parents"] = [CrashAndStress];

			m = me._instance;

			m.inService = FALSE;
			m.repairing = FALSE;

			m.exploded = FALSE;

			m.wingsAttached = TRUE;
			m.wingLoadLimitUpper = nil;
			m.wingLoadLimitLower = nil;
			m._looptimer = maketimer(0, m, m._loop);

			m.repairTimer = maketimer(10.0, m, CrashAndStress._finishRepair);
			m.repairTimer.singleShot = 1;

			m.soundWaterTimer = maketimer(3, m, CrashAndStress._impactSoundWaterEnd);
			m.soundWaterTimer.singleShot = 1;

			m.soundTimer = maketimer(3, m, CrashAndStress._impactSoundEnd);
			m.soundTimer.singleShot = 1;

			m.explodeTimer = maketimer(3, m, CrashAndStress._explodeEnd);
			m.explodeTimer.singleShot = 1;

			m.stressTimer = maketimer(3, m, CrashAndStress._stressDamageEnd);
			m.stressTimer.singleShot = 1;

			m.input = {
			#	trembleOn:  "damage/g-tremble-on",
			#	trembleMax: "damage/g-tremble-max",				
				replay:     "sim/replay/replay-state",
				lat:        "position/latitude-deg",
				lon:        "position/longitude-deg",
				alt:        "position/altitude-ft",
				altAgl:     "position/altitude-agl-ft",
				elev:       "position/ground-elev-ft",
	  			crackOn:    "damage/sounds/crack-on",
				creakOn:    "damage/sounds/creaking-on",
				crackVol:   "damage/sounds/crack-volume",
				creakVol:   "damage/sounds/creaking-volume",
				wCrashOn:   "damage/sounds/water-crash-on",
				crashOn:    "damage/sounds/crash-on",
				detachOn:   "damage/sounds/detach-on",
				explodeOn:  "damage/sounds/explode-on",
				simCrashed: "sim/crashed",
				wildfire:   "environment/wildfire/fire-on-crash",
			};
			foreach(var ident; keys(m.input)) {
			    m.input[ident] = props.globals.getNode(m.input[ident], 1);
			}

			m.fdm = nil;

			if(getprop("sim/flight-model") == "jsb") {
				m.fdm = jsbSimProp;
			} elsif(getprop("sim/flight-model") == "yasim") {
				m.fdm = yaSimProp;
			} else {
				return nil;
			}
			m.fdm.convert();
			
			m.wowStructure = [];
			m.wowGear = [];

			m.lastMessageTime = 0;

			m._initProperties();
			m._identifyGears(gears);
			m.setStressLimit(stressLimit);
			m.setWingsFailureModes(wingsFailureModes);

			m._startImpactListeners();
		} else {
			m = me._instance;
		}

		return m;
	},
	# start the system
	start: func () {
		me.inService = TRUE;
	},
	# stop the system
	stop: func () {
		me.inService = FALSE;
	},
	# return TRUE if in progress
	isStarted: func () {
		return me.inService;
	},
	# accepts a vector with failure mode IDs, they will fail when wings break off.
	setWingsFailureModes: func (modes) {
		if(modes == nil) {
			modes = [];
		}

		##
	    # Returns an actuator object that will set the serviceable property at
	    # the given node to zero when the level of failure is > 0.
	    # it will also fail additionally failure modes.

	    var set_unserviceable_cascading = func(path, casc_paths) {

	        var prop = path ~ "/serviceable";

	        if (props.globals.getNode(prop) == nil) {
	            props.globals.initNode(prop, TRUE, "BOOL");
	        } else {
	        	props.globals.getNode(prop).setBoolValue(TRUE);#in case this gets initialized empty from a recorder signal or MP alias.
	        }

	        return {
	            parents: [FailureMgr.FailureActuator],
	            mode_paths: casc_paths,
	            set_failure_level: func(level) {
	                setprop(prop, level > 0 ? 0 : 1);
	                foreach(var mode_path ; me.mode_paths) {
	                    FailureMgr.set_failure_level(mode_path, level);
	                }
	            },
	            get_failure_level: func { getprop(prop) ? 0 : 1 }
	        }
	    }

	    me.prop = me.fdm.wingsFailureID;
	    me.actuator_wings = set_unserviceable_cascading(me.prop, modes);
	    FailureMgr.add_failure_mode(me.prop, "Main wings", me.actuator_wings);
	},
	# set the stresslimit for the main wings
	setStressLimit: func (stressLimit = nil) {
		if (stressLimit != nil) {
			me.wingloadMax = stressLimit['wingloadMaxLbs'];
			me.wingloadMin = stressLimit['wingloadMinLbs'];
			me.maxG = stressLimit['maxG'];
			me.minG = stressLimit['minG'];
			me.weight = stressLimit['weightLbs'];
			if(me.wingloadMax != nil) {
				me.wingLoadLimitUpper = me.wingloadMax;
			} elsif (me.maxG != nil and me.weight != nil) {
				me.wingLoadLimitUpper = me.maxG * me.weight;
			}

			if(me.wingloadMin != nil) {
				me.wingLoadLimitLower = me.wingloadMin;
			} elsif (me.minG != nil and me.weight != nil) {
				me.wingLoadLimitLower = me.minG * me.weight;
			} elsif (me.wingLoadLimitUpper != nil) {
				me.wingLoadLimitLower = -me.wingLoadLimitUpper * 0.4;#estimate for when lower is not specified
			}
			me._looptimer.start();
		} else {
			me._looptimer.stop();
		}
	},
	# repair the aircaft
	repair: func () {
		me.failure_modes = FailureMgr._failmgr.failure_modes;
		me.mode_list = keys(me.failure_modes);

		foreach(var failure_mode_id; me.mode_list) {
			FailureMgr.set_failure_level(failure_mode_id, 0);
		}
		me.wingsAttached = TRUE;
		me.exploded = FALSE;
		me.lastMessageTime = 0;
		me.repairing = TRUE;
		me.input.simCrashed.setBoolValue(FALSE);
		me.repairTimer.restart(10.0);
	},
	_finishRepair: func () {
		me.repairing = FALSE;
	},
	_initProperties: func () {
		me.input.crackOn.setBoolValue(FALSE);
		me.input.creakOn.setBoolValue(FALSE);
		me.input.crackVol.setDoubleValue(0.0);
		me.input.creakVol.setDoubleValue(0.0);
		me.input.wCrashOn.setBoolValue(FALSE);
		me.input.crashOn.setBoolValue(FALSE);
		me.input.detachOn.setBoolValue(FALSE);
		me.input.explodeOn.setBoolValue(FALSE);
	},
	_identifyGears: func (gears) {
		me.contacts = props.globals.getNode("/gear").getChildren("gear");

		foreach(var contact; me.contacts) {
			me.index = contact.getIndex();
			me.isGear = me._contains(gears, me.index);
			me.wow = contact.getChild("wow");
			if (me.isGear == TRUE) {
				append(me.wowGear, me.wow);
			} else {
				append(me.wowStructure, me.wow);
			}
		}
	},	
	_isStructureInContact: func () {
		foreach(var structure; me.wowStructure) {
			if (structure.getBoolValue() == TRUE) {
				return TRUE;
			}
		}
		return FALSE;
	},
	_isGearInContact: func () {
		foreach(var gear; me.wowGear) {
			if (gear.getBoolValue() == TRUE) {
				return TRUE;
			}
		}
		return FALSE;
	},
	_contains: func (vector, content) {
		foreach(var vari; vector) {
			if (vari == content) {
				return TRUE;
			}
		}
		return FALSE;
	},
	_startImpactListeners: func () {
		ImpactStructureListener.crash = me;
		foreach(var structure; me.wowStructure) {
			setlistener(structure, func {call(ImpactStructureListener.run, nil, ImpactStructureListener, ImpactStructureListener)},0,0);
		}
	},
	_isRunning: func () {
		if (me.inService == FALSE or me.input.replay.getBoolValue() == TRUE or me.repairing == TRUE) {
			return FALSE;
		}
		me.time = me.fdm.input.simTime.getValue();
		if (me.time != nil and me.time > 1) {
			return TRUE;
		}
		return FALSE;
	},
	_calcGroundSpeed: func () {
  		me.realSpeed = me.fdm.getSpeedRelGround();

  		return me.realSpeed;
	},
	_impactDamage: func () {
	    me.lat = me.input.lat.getValue();
		me.lon = me.input.lon.getValue();
		me.info = geodinfo(me.lat, me.lon);
		me.solid = me.info == nil?TRUE:(me.info[1] == nil?TRUE:me.info[1].solid);
		me.speed = me._calcGroundSpeed();

		if (me.exploded == FALSE) {
			me.failure_modes = FailureMgr._failmgr.failure_modes;
		    me.mode_list = keys(me.failure_modes);
		    me.probability = (me.speed * me.speed) / 40000.0;# 200kt will fail everything, 0kt will fail nothing.
		    
		    me.hitStr = "something";
		    if(me.info != nil and me.info[1] != nil) {
			    me.hitStr = me.info[1].names == nil?"something":me.info[1].names[0];
			    foreach(infoStr; me.info[1].names) {
			    	if(find('_', infoStr) == -1) {
			    		me.hitStr = infoStr;
			    		break;
			    	}
			    }
			}
		    # test for explosion
		    if(me.probability > 0.766 and me.fdm.input.fuel.getValue() > 2500) {
		    	# 175kt+ and fuel in tanks will explode the aircraft on impact.
		    	me.input.simCrashed.setBoolValue(TRUE);
		    	me._explodeBegin("Aircraft hit "~me.hitStr~".");
		    	return;
		    }

		    foreach(var failure_mode_id; me.mode_list) {
		    	if(rand() < me.probability) {
		      		FailureMgr.set_failure_level(failure_mode_id, 1);
		      	}
		    }

			me.str = "Aircraft hit "~me.hitStr~".";
			me._output(me.str);
		} elsif (me.solid == TRUE) {
			# The aircraft is burning and will ignite the ground
			if(me.input.wildfire.getValue() == TRUE) {
				me.pos= geo.Coord.new().set_latlon(me.lat, me.lon);
				wildfire.ignite(me.pos, 1);
			}
		}
		if(me.solid == TRUE) {
			me._impactSoundBegin(me.speed);
		} else {
			me._impactSoundWaterBegin(me.speed);
		}
	},
	_impactSoundWaterBegin: func (speed) {
		if (speed > 5) {#check if sound already running?
			me.input.wCrashOn.setBoolValue(TRUE);
			me.soundWaterTimer.restart(3);
		}
	},
	_impactSoundWaterEnd: func	() {
		me.input.wCrashOn.setBoolValue(FALSE);
	},
	_impactSoundBegin: func (speed) {
		if (speed > 5) {
			me.input.crashOn.setBoolValue(TRUE);
			me.soundTimer.restart(3);
		}
	},
	_impactSoundEnd: func () {
		me.input.crashOn.setBoolValue(FALSE);
	},
	_explodeBegin: func(str) {
		me.input.explodeOn.setBoolValue(TRUE);
		me.exploded = TRUE;
		me.failure_modes = FailureMgr._failmgr.failure_modes;
	    me.mode_list = keys(me.failure_modes);

	    foreach(var failure_mode_id; me.mode_list) {
      		FailureMgr.set_failure_level(failure_mode_id, 1);
	    }
	    me.wingsAttached = FALSE;
	    me._output(str~" and exploded.", TRUE);
		
		me.explodeTimer.restart(3);
	},
	_explodeEnd: func () {
		me.input.explodeOn.setBoolValue(FALSE);
	},
	_stressDamage: func (str) {
		me._output("Aircraft damaged: Wings broke off, due to "~str~" G forces.");
		me.input.detachOn.setBoolValue(TRUE);
		
  		FailureMgr.set_failure_level(me.fdm.wingsFailureID, 1);

		me.wingsAttached = FALSE;

		me.stressTimer.restart(3);
	},
	_stressDamageEnd: func () {
		me.input.detachOn.setBoolValue(FALSE);
	},
	_output: func (str, override = FALSE) {
		me.time = me.fdm.input.simTime.getValue();
		if (override == TRUE or (me.time - me.lastMessageTime) > 3) {
			me.lastMessageTime = me.time;
			print(str);
			screen.log.write(str, 0.7098, 0.5372, 0.0);# solarized yellow
		}
	},
	_loop: func () {
		me._testStress();
		me._testWaterImpact();
	},
	_testWaterImpact: func () {
		if(me.input.altAgl.getValue() < 0) {
			me.lat = me.input.lat.getValue();
			me.lon = me.input.lon.getValue();
			me.info = geodinfo(me.lat, me.lon);
			me.solid = me.info==nil?TRUE:(me.info[1] == nil?TRUE:me.info[1].solid);
			if(me.solid == FALSE) {
				me._impactDamage();
			}
		}
	},
	_testStress: func () {
		if (me._isRunning() == TRUE and me.wingsAttached == TRUE) {
			me.gForce = me.fdm.input.Nz.getValue() == nil?1:me.fdm.input.Nz.getValue();
			me.weight = me.fdm.input.weight.getValue();
			me.wingload = me.gForce * me.weight;

			me.broken = FALSE;

			if(me.wingload < 0) {
				me.broken = me._testWingload(-me.wingload, -me.wingLoadLimitLower);
				if(me.broken == TRUE) {
					me._stressDamage("negative");
				}
			} else {
				me.broken = me._testWingload(me.wingload, me.wingLoadLimitUpper);
				if(me.broken == TRUE) {
					me._stressDamage("positive");
				}
			}
		} else {
			me.input.crackOn.setBoolValue(FALSE);
			me.input.creakOn.setBoolValue(FALSE);
			#me.input.trembleOn.setValue(0);
		}
	},
	_testWingload: func (wingloadCurr, wingLoadLimit) {
		if (wingloadCurr > (wingLoadLimit * 0.5)) {
			#me.input.trembleOn.setValue(1);
			me.tremble_max = math.sqrt((wingloadCurr - (wingLoadLimit * 0.5)) / (wingLoadLimit * 0.5));
			#me.input.trembleMax.setDoubleValue(1);

			if (wingloadCurr > (wingLoadLimit * 0.75)) {

				#me.tremble_max = math.sqrt((wingloadCurr - (wingLoadLimit * 0.5)) / (wingLoadLimit * 0.5));
				me.input.creakVol.setDoubleValue(me.tremble_max);
				me.input.creakOn.setBoolValue(TRUE);

				if (wingloadCurr > (wingLoadLimit * 0.90)) {
					me.input.crackOn.setBoolValue(TRUE);
					me.input.crackVol.setDoubleValue(me.tremble_max);
					if (wingloadCurr > wingLoadLimit) {
						me.input.crackVol.setDoubleValue(1);
						me.input.creakVol.setDoubleValue(1);
						#me.input.trembleMax.setDoubleValue(1);
						return TRUE;
					}
				} else {
					me.input.crackOn.setBoolValue(FALSE);
				}
			} else {
				me.input.creakOn.setBoolValue(FALSE);
			}
		} else {
			me.input.crackOn.setBoolValue(FALSE);
			me.input.creakOn.setBoolValue(FALSE);
			#me.input.trembleOn.setValue(0);
		}
		return FALSE;
	},
};


var ImpactStructureListener = {
	crash: nil,
	run: func () {
		if (crash._isRunning() == TRUE) {
			var wow = crash._isStructureInContact();
			if (wow == TRUE) {
				crash._impactDamage();
			}
		}
	},
};


# static class
var fdmProperties = {
	input: {},
	convert: func () {
		foreach(var ident; keys(me.input)) {
		    me.input[ident] = props.globals.getNode(me.input[ident], 1);
		}
	},
	fps2kt: func (fps) {
		return fps * FPS2KT;
	},
	getSpeedRelGround: func () {
		return 0;
	},
	wingsFailureID: nil,
};

var jsbSimProp = {
	parents: [fdmProperties],
	input: {
				weight:     "fdm/jsbsim/inertia/weight-lbs",
				fuel:       "fdm/jsbsim/propulsion/total-fuel-lbs",
				simTime:    "fdm/jsbsim/simulation/sim-time-sec",
				northFps:   "velocities/speed-north-fps",
				eastFps:    "velocities/speed-east-fps",
				downFps:    "velocities/speed-down-fps",
				Nz:         "fdm/jsbsim/accelerations/Nz",
	},
	getSpeedRelGround: func () {
		me.northSpeed = me.input.northFps.getValue();
		me.eastSpeed  = me.input.eastFps.getValue();
		me.horzSpeed  = math.sqrt((me.eastSpeed * me.eastSpeed) + (me.northSpeed * me.northSpeed));
  		me.vertSpeed  = me.input.downFps.getValue();
  		me.realSpeed  = me.fps2kt(math.sqrt((me.horzSpeed * me.horzSpeed) + (me.vertSpeed * me.vertSpeed)));

  		return me.realSpeed;
	},
	wingsFailureID: "fdm/jsbsim/structural/wings",
};

var yaSimProp = {
	parents: [fdmProperties],
	input: {
				weight:     "yasim/gross-weight-lbs",
				fuel:       "consumables/fuel/total-fuel-lbs",
				simTime:    "sim/time/elapsed-sec",
				northFps:   "velocities/speed-north-fps",
				eastFps:    "velocities/speed-east-fps",
				downFps:    "velocities/speed-down-fps",
				Nz:         "accelerations/n-z-cg-fps_sec",
	},
	getSpeedRelGround: func () {
		me.northSpeed = me.input.northFps.getValue();
		me.eastSpeed  = me.input.eastFps.getValue();
		me.horzSpeed  = math.sqrt((me.eastSpeed * me.eastSpeed) + (me.northSpeed * me.northSpeed));
  		me.vertSpeed  = me.input.downFps.getValue();
  		me.realSpeed  = me.fps2kt(math.sqrt((me.horzSpeed * me.horzSpeed) + (me.vertSpeed * me.vertSpeed)));

  		return me.realSpeed;
	},
	wingsFailureID: "structural/wings",
};


# TODO:
#
# Loss of inertia if impacting/sliding? Or should the jsb groundcontacts take care of that alone?
# If gears hit something at too high speed the gears should be damaged?
# Make property to control if system active, or method enough?
# Explosion depending on bumpiness and speed when sliding?
# Tie in with damage from Bombable?
# Use galvedro's UpdateLoop framework when it gets merged


# example uses:
#
# var crashCode = CrashAndStress.new([0,1,2]); 
#
# var crashCode = CrashAndStress.new([0,1,2], {"weightLbs":30000, "maxG": 12});
#
# var crashCode = CrashAndStress.new([0,1,2,3], {"weightLbs":20000, "maxG": 11, "minG": -5});
#
# var crashCode = CrashAndStress.new([0,1,2], {"wingloadMaxLbs": 90000, "wingloadMinLbs": -45000}, ["controls/flight/aileron", "controls/flight/elevator", "controls/flight/flaps"]);
#
# var crashCode = CrashAndStress.new([0,1,2], {"wingloadMaxLbs":90000}, ["controls/flight/aileron", "controls/flight/elevator", "controls/flight/flaps"]);
#
# Gears parameter must be defined.
# Stress parameter is optional. If minimum wing stress is not defined it will be set to -40% of max wingload stress if that is defined.
# The last optional parameter is a list of failure mode IDs that shall fail when wings detach. They must be defined in the FailureMgr.
#
#
# Remember to add sounds and to add the sound properties as custom signals to the replay recorder.


# use:
var crashCode = nil;
var crash_start = func {
	removelistener(lsnr);
    if (variant.JA) {
        crashCode = CrashAndStress.new([0,1,2], {"weightLbs": 35000, "maxG": 10.5, "minG": -4.5}, ["controls/gear1", "controls/gear2", "controls/flight/left-elevon", "controls/flight/right-elevon"]);
    } else {
        crashCode = CrashAndStress.new([0,1,2], {"weightLbs": 33000, "maxG": 9, "minG": -3}, ["controls/gear1", "controls/gear2", "controls/flight/left-elevon", "controls/flight/right-elevon"]);
    }
    crashCode.start();
}

var lsnr = setlistener("ja37/supported/initialized", crash_start);

# test:
var repair = func {
	crashCode.repair();
};

var exp = func {
	if (crashCode.exploded==0) {
		crashCode._explodeBegin("Aircraft was abandoned ");
	}
};
