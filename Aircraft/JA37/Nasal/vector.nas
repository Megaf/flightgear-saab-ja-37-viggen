var Math = {
    #
    # Authors: Nikolai V. Chr, Axel Paccalin.
    #
    # Version 2.01
    #
    # When doing euler coords. to cartesian: +x = forw, +y = left,  +z = up.
    # FG struct. coords:                     +x = back, +y = right, +z = up.
    #
    # If euler to cartesian (with inverted heading) then:
    # cartesian vector will be x: north, y: west, z: skyward
    #
    # When doing euler angles (from pilots point of view):  yaw     = yaw left,  pitch = rotate up, roll = roll right.
    # FG rotations:                                         heading = yaw right, pitch = rotate up, roll = roll right.
    #
    # Cartesian is right-handed coord system.
    #
    clamp: func(v, min, max) { v < min ? min : v > max ? max : v },

    convertCoords: func (x,y,z) {
        return [-x, -y, z];
    },

    convertAngles: func (heading,pitch,roll) {
        return [-heading, pitch, roll];
    },
    
    # returns direction in geo coordinate system
    vectorToGeoVector: func (a, coord) {
        me.handp = me.cartesianToEuler(a);
        me.end_dist_m = 100;# not too low for floating point precision. Not too high to get into earth curvature stuff.
        me.tgt_coord = geo.Coord.new(coord);
        if (me.handp[0] != nil) {
            me.tgt_coord.apply_course_distance(me.handp[0],me.end_dist_m);
            me.upamount = me.end_dist_m * math.tan(me.handp[1]*D2R);
        } elsif (me.handp[1] == 90) {
            me.upamount = me.end_dist_m;
        } else {
            me.upamount = -me.end_dist_m;
        }
        me.tgt_coord.set_alt(coord.alt()+me.upamount);
        me.geoVeccy = me.product(me.magnitudeVector(a), me.normalize([me.tgt_coord.x()-coord.x(),me.tgt_coord.y()-coord.y(),me.tgt_coord.z()-coord.z()]));
        return {"x":me.tgt_coord.x()-coord.x(),  "y":me.tgt_coord.y()-coord.y(), "z":me.tgt_coord.z()-coord.z(), "vector": me.geoVeccy};
    },
    
    # When observing another MP aircraft the groundspeed velocity info is in body frame, this method will convert it to cartesian vector.
    #
    # Warning: If you input body velocities in fps the output will be in fps also. Likewise for mps.
    getCartesianVelocity: func (yaw_deg, pitch_deg, roll_deg, uBody_fps, vBody_fps, wBody_fps) {
        me.bodyVelocity = [uBody_fps, -vBody_fps, -wBody_fps];
        return me.rollPitchYawVector(roll_deg, pitch_deg, yaw_deg, me.bodyVelocity);
    },

    # angle between 2 vectors. Returns 0-180 degrees.
    angleBetweenVectors: func (a,b) {
        a = me.normalize(a);
        b = me.normalize(b);
        me.value = me.clamp((me.dotProduct(a,b)/me.magnitudeVector(a))/me.magnitudeVector(b),-1,1);#just to be safe in case some floating point error makes it out of bounds
        return R2D * math.acos(me.value);
    },

    # Rodrigues' rotation formula. Use unitVectorAxis as axis, and rotate around it.
    rotateVectorAroundVector: func (a, unitVectorAxis, angle) {
        return  me.plus(
                    me.plus(
                        me.product(math.cos(angle*D2R),a),
                        me.product(math.sin(angle*D2R), me.crossProduct(unitVectorAxis,a))
                    ),
                    me.product((1-math.cos(angle*D2R))*me.dotProduct(unitVectorAxis,a), unitVectorAxis)
                );
    },

    #Rotate a certain amound of degrees towards 'towardsMe'.
    rotateVectorTowardsVector: func (a, towardsMe, angle) {
        return me.rotateVectorAroundVector(a, me.normalize(me.crossProduct(a, towardsMe)), angle);
    },

    # length of vector
    magnitudeVector: func (a) {
        me.mag = 1;
        call(func {me.mag = math.sqrt(math.pow(a[0],2)+math.pow(a[1],2)+math.pow(a[2],2))},nil,nil,var err =[]);#strange bug in Nasal can sometimes mess up sqrt
        return me.mag;
    },

    # dot product of 2 vectors
    dotProduct: func (a,b) {
        return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];
    },

    # rotate a vector. Order: roll, pitch, yaw (same as aircraft)
    #
    # The coordinate system is fixed during all the rolls.
    #
    rollPitchYawVector: func (roll, pitch, yaw, vector) {
        me.rollM  = me.rollMatrix(roll);
        me.pitchM = me.pitchMatrix(pitch);
        me.yawM   = me.yawMatrix(yaw);
        me.rotation = me.multiplyMatrices(me.yawM, me.multiplyMatrices(me.pitchM, me.rollM));
        return me.multiplyMatrixWithVector(me.rotation, vector);
    },

    # rotate a vector. Order: yaw, pitch, roll (reverse of aircraft)
    yawPitchRollVector: func (yaw, pitch, roll, vector) {
        me.rollM  = me.rollMatrix(roll);
        me.pitchM = me.pitchMatrix(pitch);
        me.yawM   = me.yawMatrix(yaw);
        me.rotation = me.multiplyMatrices(me.rollM, me.multiplyMatrices(me.pitchM, me.yawM));
        return me.multiplyMatrixWithVector(me.rotation, vector);
    },

    # rotate a vector. Order: yaw, pitch
    yawPitchVector: func (yaw, pitch, vector) {
        me.pitchM = me.pitchMatrix(pitch);
        me.yawM   = me.yawMatrix(yaw);
        me.rotation = me.multiplyMatrices(me.pitchM, me.yawM);
        return me.multiplyMatrixWithVector(me.rotation, vector);
    },

    # rotate a vector. Order: pitch, yaw
    pitchYawVector: func (pitch, yaw, vector) {
        me.pitchM = me.pitchMatrix(pitch);
        me.yawM   = me.yawMatrix(yaw);
        me.rotation = me.multiplyMatrices(me.yawM, me.pitchM);
        return me.multiplyMatrixWithVector(me.rotation, vector);
    },

    # rotate a vector. Order: yaw
    yawVector: func (yaw, vector) {
        me.yawM   = me.yawMatrix(yaw);
        return me.multiplyMatrixWithVector(me.yawM, vector);
    },

    # rotate a vector. Order: pitch
    pitchVector: func (pitch, vector) {
        me.pitchM = me.pitchMatrix(pitch);
        return me.multiplyMatrixWithVector(me.pitchM, vector);
    },

    # multiply 3x3 matrix with vector
    multiplyMatrixWithVector: func (matrix, vector) {
        return [matrix[0]*vector[0]+matrix[1]*vector[1]+matrix[2]*vector[2],
                matrix[3]*vector[0]+matrix[4]*vector[1]+matrix[5]*vector[2],
                matrix[6]*vector[0]+matrix[7]*vector[1]+matrix[8]*vector[2]];
    },

    # multiply 2 3x3 matrices
    multiplyMatrices: func (a,b) {
        return [a[0]*b[0]+a[1]*b[3]+a[2]*b[6], a[0]*b[1]+a[1]*b[4]+a[2]*b[7], a[0]*b[2]+a[1]*b[5]+a[2]*b[8],
                a[3]*b[0]+a[4]*b[3]+a[5]*b[6], a[3]*b[1]+a[4]*b[4]+a[5]*b[7], a[3]*b[2]+a[4]*b[5]+a[5]*b[8],
                a[6]*b[0]+a[7]*b[3]+a[8]*b[6], a[6]*b[1]+a[7]*b[4]+a[8]*b[7], a[6]*b[2]+a[7]*b[5]+a[8]*b[8]];
    },

    # matrix for rolling
    rollMatrix: func (roll) {
        roll = roll * D2R;
        return [1,0,0,
                0,math.cos(roll),-math.sin(roll),
                0,math.sin(roll), math.cos(roll)];
    },

    # matrix for pitching
    pitchMatrix: func (pitch) {
        pitch = -pitch * D2R;
        return [math.cos(pitch),0,math.sin(pitch),
                0,1,0,
                -math.sin(pitch),0,math.cos(pitch)];
    },

    # matrix for yawing
    yawMatrix: func (yaw) {
        yaw = yaw * D2R;
        return [math.cos(yaw),-math.sin(yaw),0,
                math.sin(yaw),math.cos(yaw),0,
                0,0,1];
    },

    # vector to heading/pitch
    cartesianToEuler: func (vector) {
        me.horz  = math.sqrt(vector[0]*vector[0]+vector[1]*vector[1]);
        if (me.horz != 0) {
            me.pitch = math.atan2(vector[2],me.horz)*R2D;
            me.div = math.clamp(-vector[1]/me.horz, -1, 1);
            me.hdg = math.asin(me.div)*R2D;

            if (vector[0] < 0) {
                # south
                if (me.hdg >= 0) {
                    me.hdg = 180-me.hdg;
                } else {
                    me.hdg = -180-me.hdg;
                }
            }
            me.hdg = geo.normdeg(me.hdg);
        } else {
            me.pitch = vector[2]>=0?90:-90;
            me.hdg = nil;
        }
        return [me.hdg, me.pitch];
    },

    # vector to pitch
    cartesianToEulerPitch: func (vector) {
        me.horz  = math.sqrt(vector[0]*vector[0]+vector[1]*vector[1]);
        if (me.horz != 0) {
            me.pitch = math.atan2(vector[2],me.horz)*R2D;
        } else {
            me.pitch = vector[2]>=0?90:-90;
        }
        return me.pitch;
    },

    # vector to heading
    cartesianToEulerHeading: func (vector) {
        me.horz  = math.sqrt(vector[0]*vector[0]+vector[1]*vector[1]);
        if (me.horz != 0) {
            me.div = math.clamp(-vector[1]/me.horz, -1, 1);
            me.hdg = math.asin(me.div)*R2D;

            if (vector[0] < 0) {
                # south
                if (me.hdg >= 0) {
                    me.hdg = 180-me.hdg;
                } else {
                    me.hdg = -180-me.hdg;
                }
            }
            me.hdg = geo.normdeg(me.hdg);
        } else {
            me.hdg = 0;
        }
        return me.hdg;
    },

    # gives an vector that points up from fuselage
    eulerToCartesian3Z: func (yaw_deg, pitch_deg, roll_deg) {
        me.yaw   = yaw_deg     * D2R;
        me.pitch = pitch_deg   * D2R;
        me.roll  = roll_deg    * D2R;
        me.x = -math.cos(me.yaw)*math.sin(me.pitch)*math.cos(me.roll) + math.sin(me.yaw)*math.sin(me.roll);
        me.y = -math.sin(me.yaw)*math.sin(me.pitch)*math.cos(me.roll) - math.cos(me.yaw)*math.sin(me.roll);
        me.z =  math.cos(me.pitch)*math.cos(me.roll);#roll changed from sin to cos, since the rotation matrix is wrong
        return [me.x,me.y,me.z];
    },

    # gives an vector that points forward from fuselage
    eulerToCartesian3X: func (yaw_deg, pitch_deg, roll_deg) {
        me.yaw   = yaw_deg     * D2R;
        me.pitch = pitch_deg   * D2R;
        me.roll  = roll_deg    * D2R;
        me.x = math.cos(me.yaw)*math.cos(me.pitch);
        me.y = math.sin(me.yaw)*math.cos(me.pitch);
        me.z = math.sin(me.pitch);
        return [me.x,me.y,me.z];
    },

    # gives an vector that points left from fuselage
    eulerToCartesian3Y: func (yaw_deg, pitch_deg, roll_deg) {
        me.yaw   = yaw_deg     * D2R;
        me.pitch = pitch_deg   * D2R;
        me.roll  = roll_deg    * D2R;
        me.x = -math.cos(me.yaw)*math.sin(me.pitch)*math.sin(me.roll) - math.sin(me.yaw)*math.cos(me.roll);
        me.y = -math.sin(me.yaw)*math.sin(me.pitch)*math.sin(me.roll) + math.cos(me.yaw)*math.cos(me.roll);
        me.z =  math.cos(me.pitch)*math.sin(me.roll);
        return [me.x,me.y,me.z];
    },

    # same as eulerToCartesian3X, except it needs no roll
    eulerToCartesian2: func (yaw_deg, pitch_deg) {
        me.yaw   = yaw_deg     * D2R;
        me.pitch = pitch_deg   * D2R;
        me.x = math.cos(me.pitch) * math.cos(me.yaw);
        me.y = math.cos(me.pitch) * math.sin(me.yaw);
        me.z = math.sin(me.pitch);
        return [me.x,me.y,me.z];
    },

    #pitch from coord1 to coord2 in degrees (takes curvature of earth into effect.)
    getPitch: func (coord1, coord2) {      
      if (coord1.lat() == coord2.lat() and coord1.lon() == coord2.lon()) {
        if (coord2.alt() > coord1.alt()) {
          return 90;
        } elsif (coord2.alt() < coord1.alt()) {
          return -90;
        } else {
          return 0;
        }
      }
      if (coord1.alt() != coord2.alt()) {
        me.d12 = coord1.direct_distance_to(coord2);
        me.coord3 = geo.Coord.new(coord1);
        me.coord3.set_alt(coord1.alt()-me.d12*0.5);# this will increase the area of the triangle so that rounding errors dont get in the way.
        me.d13 = coord1.alt()-me.coord3.alt();        
        if (me.d12 == 0) {
            # on top of each other, maybe rounding error..
            return 0;
        }
        me.d32 = me.coord3.direct_distance_to(coord2);
        if (math.abs(me.d13)+me.d32 < me.d12) {
            # rounding errors somewhere..one triangle side is longer than other 2 sides combined.
            return 0;
        }
        # standard formula for a triangle where all 3 side lengths are known:
        me.len = (math.pow(me.d12, 2)+math.pow(me.d13,2)-math.pow(me.d32, 2))/(2 * me.d12 * math.abs(me.d13));
        if (me.len < -1 or me.len > 1) {
            # something went wrong, maybe rounding error..
            return 0;
        }
        me.angle = R2D * math.acos(me.len);
        me.pitch = -1* (90 - me.angle);
        #printf("d12 %.4f  d32 %.4f  d13 %.4f len %.4f pitch %.4f angle %.4f", me.d12, me.d32, me.d13, me.len, me.pitch, me.angle);
        return me.pitch;
      } else {
        # same altitude
        me.nc = geo.Coord.new();
        me.nc.set_xyz(0,0,0);        # center of earth
        me.radiusEarth = coord1.direct_distance_to(me.nc);# current distance to earth center
        me.d12 = coord1.direct_distance_to(coord2);
        # standard formula for a triangle where all 3 side lengths are known:
        me.len = (math.pow(me.d12, 2)+math.pow(me.radiusEarth,2)-math.pow(me.radiusEarth, 2))/(2 * me.d12 * me.radiusEarth);
        if (me.len < -1 or me.len > 1) {
            # something went wrong, maybe rounding error..
            return 0;
        }
        me.angle = R2D * math.acos(me.len);
        me.pitch = -1* (90 - me.angle);
        return me.pitch;
      }
    },

    # supply a normal to the plane, and a vector. The vector will be projected onto the plane, and that projection is returned as a vector.
    projVectorOnPlane: func (planeNormal, vector) {
      if (me.magnitudeVector(planeNormal) == 0) return [0,0,0];#safety
      return me.minus(vector, me.product(me.dotProduct(vector,planeNormal)/math.pow(me.magnitudeVector(planeNormal),2), planeNormal));
    },

    # Project a onto ontoMe.
    projVectorOnVector: func (a, ontoMe) {
      if (me.magnitudeVector(ontoMe) == 0) return [0,0,0];#safety
      return me.product(me.dotProduct(a,ontoMe)/me.dotProduct(ontoMe,ontoMe), ontoMe);
    },

    # Project a onto ontoMe and measure how long along ontoMe it goes, opposite will give negative number.
    scalarProjVectorOnVector: func (a, ontoMe) {
      me.ontoMeMag = me.magnitudeVector(ontoMe);
      if (me.ontoMeMag == 0) return 0;
      return me.dotProduct(a,ontoMe)/me.ontoMeMag;
    },
    
    # unary - vector
    opposite: func (v){
        # author: Paccalin
        return [-v[0], -v[1], -v[2]];
    },

    # vector a - vector b
    minus: func (a, b) {
      return [a[0]-b[0], a[1]-b[1], a[2]-b[2]];
    },

    # vector a + vector b
    plus: func (a, b) {
      return [a[0]+b[0], a[1]+b[1], a[2]+b[2]];
    },

    # float * vector
    product: func (scalar, vector) {
      return [scalar*vector[0], scalar*vector[1], scalar*vector[2]]
    },

    # print vector to console
    format: func (v) {
      return sprintf("(%.2f, %.2f, %.2f)",v[0],v[1],v[2]);
    },

    # make vector length 1.0
    normalize: func (v) {
      me.mag = me.magnitudeVector(v);
      return [v[0]/me.mag, v[1]/me.mag, v[2]/me.mag];
    },
    
    crossProduct: func (a,b) {
        return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
    },
    
    distance_from_point_to_line: func (coordP, coordL1, coordL2) {
        var P  = [coordP.x(),  coordP.y(),  coordP.z()];
        var L1 = [coordL1.x(), coordL1.y(), coordL1.z()];
        var L2 = [coordL2.x(), coordL2.y(), coordL2.z()];
        
        return me.magnitudeVector(me.crossProduct(me.minus(L2,L1), me.minus(L1,P)))/me.magnitudeVector(me.minus(L2,L1));
    },

    interpolateVector: func (start, end, fraction) {
        me.xx = (start[0]*(1-fraction) +end[0]*fraction);
        me.yy = (start[1]*(1-fraction) +end[1]*fraction);
        me.zz = (start[2]*(1-fraction) +end[2]*fraction);

        return [me.xx, me.yy, me.zz];
    },

    # move distance 'along' from start towards end. Total dist from start to end is dist.
    alongVector: func (start, end, dist, along) {
        me.fraction = along/dist;
        return me.interpolateVector(start, end, me.fraction);
    },
    
    # Orthogonal projection of a vector `vec` onto another `ref` !!can throw an exception if the referential vector is null!!.
    orthogonalProjection: func(vec, ref){
      # author: Paccalin
      me.op_refMag = me.magnitudeVector(ref);
      if(me.op_refMag == 0)
        die("Orthogonal projection on a null vector referential");

      return me.dotProduct(vec, ref) / me.op_refMag;
    },

    # Time at which two particles will be at shortest distance !!can throw an exception if the relative speed is null!!
    particleShortestDistTime: func (orig1, speed1, orig2, speed2) {
      # author: Paccalin
      # Compute the origin of the second particle in a referential positionally centered on the first particle.
      me.psdt_tgtOrig = me.minus(orig2, orig1);
      # Compute the speed of the second particle in a referential inertially based on the first particle.
      me.psdt_tgtSpeed = me.minus(speed2, speed1);

      # Project the origin of the particle1 referential onto the line supported by the particle2 trajectory in 1 unit of time.
      # And divide the result by the magnitude of the speed to have it normalized relative to the time.
      return me.orthogonalProjection(me.opposite(me.psdt_tgtOrig), me.psdt_tgtSpeed) / me.magnitudeVector(me.psdt_tgtSpeed);
    },

    # forward and up are vectors defining a 3D frame.
    # Compute azimuth and elevation of 'vector' in this frame.
    #
    # remarks: unpredictable result if up / forward are not orthogonal.
    # Azimuth and elevation are in radian.
    # Elevation is the angle (vector, up), 90 if vector and up are aligned, = -90 if opposed.
    # Azimuth is the angle (vector, forward) after projection orthogonally to 'up'.
    #
    vectorAziElevInFwdUpFrame: func(vec, forward, up) {
        me.elev = 90 - me.angleBetweenVectors(vec, up);
        vec = me.projVectorOnPlane(up, vec);
        if (me.magnitudeVector(vec) < 0.0001) {
            me.azi = 0;
        } else {
            me.azi = me.angleBetweenVectors(vec, forward);
            me.sign = me.dotProduct(up, me.crossProduct(vec, forward));
            if (me.sign < 0) me.azi = -me.azi;
        }
        return [me.azi, me.elev];
    },

# rotation matrices
#
#
#| 1    0          0      |
#| 0 cos(roll) -sin(roll) |
#| 0 sin(roll)  cos(roll) |
#
#| cos(-pitch) 0  sin(-pitch) |
#|     0       1       0      |
#| -sin(-pitch) 0 cos(-pitch) |
#
#| cos(yaw) -sin(yaw) 0 |
#| sin(yaw)  cos(yaw) 0 |
#|    0         0     1 |
#
# combined matrix from yaw, pitch, roll:
#
#| cos(yaw)cos(pitch) -cos(yaw)sin(pitch)sin(roll)-sin(yaw)cos(roll) -cos(yaw)sin(pitch)cos(roll)+sin(yaw)sin(roll)|
#| sin(yaw)cos(pitch) -sin(yaw)sin(pitch)sin(roll)+cos(yaw)cos(roll) -sin(yaw)sin(pitch)cos(roll)-cos(yaw)sin(roll)|
#| sin(pitch)          cos(pitch)sin(roll)                            cos(pitch)cos(roll)|
#
#

};


### Own aircraft position and attitude, stored as XYZ vectors.
#
# This allows to compute quickly azimuth / elevation in local frame to a coordinate.

var AircraftPosition = {
    time_prop: props.globals.getNode("sim/time/elapsed-sec"),
    last_time: -1,

    update: func {
        me.ac_pos = geo.aircraft_position();
        var tmp = aircraftToCart({x: 1000, y: 0, z: 0, });
        me.xyz_vec_fwd = [
            tmp.x - me.ac_pos.x(),
            tmp.y - me.ac_pos.y(),
            tmp.z - me.ac_pos.z(),
        ];
        tmp = aircraftToCart({x: 0, y: 0, z: -1000, });
        me.xyz_vec_up = [
            tmp.x - me.ac_pos.x(),
            tmp.y - me.ac_pos.y(),
            tmp.z - me.ac_pos.z(),
        ];
    },

    coordToLocalAziElev: func(coord) {
        me.time = me.time_prop.getValue();
        if (me.time != me.last_time) {
            me.update();
            me.last_time = me.time;
        }

        me.vec = Math.minus(coord.xyz(), me.ac_pos.xyz());
        return Math.vectorAziElevInFwdUpFrame(me.vec, me.xyz_vec_fwd, me.xyz_vec_up);
    },
};


var unitTest = {
    start: func {
        # 1: Simple test of rotation matrices and getting the input back in another way.
        var localDir = Math.pitchYawVector(-40, -75, [1,0,0]);
        me.eulerDir = Math.cartesianToEuler(localDir);
        me.eulerDir[0] = me.eulerDir[0]==nil?0:geo.normdeg(me.eulerDir[0]);
        printf("Looking out of aircraft window at heading 75 and 40 degs down: %.4f heading %.4f pitch.",me.eulerDir[0],me.eulerDir[1]);
        # 2: Revert part of test #1
        var forwardDir = Math.yawPitchVector(75, 0, localDir);
        me.eulerDir = Math.cartesianToEuler(forwardDir);
        me.eulerDir[0] = me.eulerDir[0]==nil?0:geo.normdeg(me.eulerDir[0]);
        printf("Looking out of aircraft window at heading 0 and 40 degs down: %.4f heading %.4f pitch.",me.eulerDir[0],me.eulerDir[1]);
        # 3: Tougher test, try it different places on earth since earth is not sphere. At KXTA runway it gives 0.03% error in pitch.
        var someDir = Math.eulerToCartesian3X(-75, -40, 20);
        var myCoord = geo.aircraft_position();
        me.thousandVectorGeo = Math.vectorToGeoVector(someDir, myCoord).vector;# does not return magnitude with meaning, only its direction matters.
        me.thousandVectorGeo = Math.normalize(me.thousandVectorGeo);
        me.thousandVectorGeo = Math.product(100000, me.thousandVectorGeo);
        me.lookAt = geo.Coord.new().set_xyz(myCoord.x()+me.thousandVectorGeo[0], myCoord.y()+me.thousandVectorGeo[1], myCoord.z()+me.thousandVectorGeo[2]);
        printf("Looking out of aircraft window 100000m away heading 75 and 40 degs down: %.4f heading %.4f pitch %.4f meter.", myCoord.course_to(me.lookAt), Math.getPitch(myCoord, me.lookAt), myCoord.direct_distance_to(me.lookAt));
        # 4: 
        var aircraft = Math.eulerToCartesian3X(-35, 72, 21);
        var aircraft2 = Math.rollPitchYawVector(21, 72, -35, [1,0,0]);
        printf("These two should be the same %s = %s",Math.format(aircraft),Math.format(aircraft2));
    },
};
#unitTest.start();
