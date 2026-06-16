/// Pure-Dart engine for SGP4 satellite propagation, topocentric look-angles,
/// pass prediction, and naked-eye visibility.
///
/// This is the public barrel - the only entry point consumers import. The L1
/// propagation layer (orbital elements, the SGP4/SDP4 engine, and the TEME
/// state it produces) is exported here.
library;

export 'src/domain/eci_state.dart' show EciState;
export 'src/domain/failures.dart'
    show
        GeometryException,
        InvalidElementsException,
        PropagationException,
        SatelliteObserverException;
export 'src/domain/geo/observer.dart' show Observer;
export 'src/domain/geo/vector3.dart' show Vector3;
export 'src/domain/gp_elements.dart' show GpElements;
export 'src/domain/look_angle.dart' show LookAngle;
export 'src/domain/pass.dart' show Pass, PassEvent, PassEventKind;
export 'src/domain/sub_point.dart' show SubSatellitePoint;
export 'src/facade/satellite_observer.dart' show HorizonMask, SatelliteObserver;
export 'src/propagation/propagation_engine.dart' show PropagationEngine;
export 'src/propagation/sgp4/gravity_constants.dart' show GravityModel;
export 'src/propagation/sgp4/sgp4_engine.dart' show Sgp4Engine;
