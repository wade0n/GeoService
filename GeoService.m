//
//  GeoService.m
//  MyHome
//
//  Created by Дмитрий Калашников on 10/28/13.
//
//

#import "GeoService.h"
#import "RKXMLDictionarySerialization.h"
#import <CoreLocation/CoreLocation.h>
#import "GeoData.h"
#import "Flurry.h"
#import "GeoResponseData.h"




#define GEO_DEFAULT_DISTANCE_FILTER 300


@implementation GeoService


+ (instancetype)sharedGeoService
{
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}


- (id)init{
    
    self = [super init];
    
    if (self) {
        isTacking = NO;
        [self startStandardUpdates];
    }
    return self;
}


- (void)refresh{
    [self startStandardUpdates];
}
- (void)startStandardUpdates

{
    
    // Create the location manager if this object does not

    // already have one.
    
    if (nil == _locationManager){
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        _locationManager.activityType = CLActivityTypeOther;
        // Set a movement threshold for new events.
        _locationManager.distanceFilter = GEO_DEFAULT_DISTANCE_FILTER; // meters
        
        geoCoder = [[CLGeocoder alloc] init];
    }
    
    
        
        
    [_locationManager startUpdatingLocation];
}


- (void)configureNetwork{
    
    
    
    
    networkEngine = [RKObjectManager managerWithBaseURL:[NSURL URLWithString:GEO_API_URL]];
    [networkEngine.HTTPClient setAuthorizationHeaderWithUsername:GEO_LOGIN password:GEO_PASSWORD];

    [RKMIMETypeSerialization registerClass:[RKXMLDictionarySerialization class] forMIMEType:RKMIMETypeTextXML];
    [RKXMLDictionarySerialization sharedParser].attributesMode = XMLDictionaryAttributesModePrefixed;
    
    [networkEngine setAcceptHeaderWithMIMEType:RKMIMETypeTextXML];
    [AFNetworkActivityIndicatorManager sharedManager].enabled = YES;
    
    /* Logging RestKit */
    
//    // Log all HTTP traffic with request and response bodies
//    RKLogConfigureByName("RestKit/Network", RKLogLevelTrace);
//    
//    // Log debugging info about Core Data
//    RKLogConfigureByName("RestKit/CoreData", RKLogLevelDebug);
//    
//    // Log only critical messages from the Object Mapping component
//    RKLogConfigureByName("RestKit/ObjectMapping", RKLogLevelDebug);
//    
    
    
    
}


- (void)startGeoTracking{
    _locationManager.distanceFilter = 300;
    isTacking = YES;
    [self startStandardUpdates];
    
}

- (void)stopGeoTracking{
    isTacking = NO;
   
}


- (void)getGeoCoordinatesIfSuccess:(void (^)(float latitude, float longtitude, NSString *countryStr, NSString *cityStr, NSString *streetStr, NSString *houseStr))success failure:(void (^)(NSError *error))failure{
    
    
    if (success) {
        self.geoSuccess = success;
    }
    
    if (failure) {
        self.geoFailure = failure;
    }
    
    
};

- (void)dealloc{
    [_locationManager stopUpdatingLocation];
}


- (void)sendGeoReuestWithLatitude:(CGFloat)latitude andLongitude:(CGFloat)longitude{
    
    if (!networkEngine) {
        [self configureNetwork];
    }
    
    NSString *requestString = @"";
    if ((latitude != 0.0f && latitude != 0.0f)) {
        requestString = [requestString stringByAppendingString:GEO_REQUEST_WITH_COORDINATES(latitude, longitude)];
    }
    else{
        requestString = [requestString stringByAppendingString:GEO_REQUEST];
    }
    
    
    RKObjectMapping *mapping = [GeoService getObjectMapping];
    NSIndexSet *statusCodes = RKStatusCodeIndexSetForClass(RKStatusCodeClassSuccessful); // Anything in 2xx
    RKResponseDescriptor *articleDescriptor = [RKResponseDescriptor responseDescriptorWithMapping:mapping method:RKRequestMethodAny pathPattern:@"/geo" keyPath:@"kmdata.geoservice" statusCodes:statusCodes];
    
    [networkEngine addResponseDescriptor:articleDescriptor];
    
    GeoService *selfCaptured = self;
    
    
    [networkEngine getObjectsAtPath:requestString parameters:nil success:^(RKObjectRequestOperation *operation, RKMappingResult *mappingResult) {
        
        if (mappingResult.count) {
            
            
            selfCaptured.responses = ((GeoService *)[mappingResult firstObject]).responses;
            selfCaptured.version = ((GeoService *)[mappingResult firstObject]).version;
            responceData = [selfCaptured.responses firstObject];
        }
        
        
        NSLocale *loc = [NSLocale currentLocale];

        
        if (!_geoLocData) {
            _geoLocData = [[GeoData alloc] init];
            _geoLocData.lastTime = [NSDate date];
            _geoLocData.latitude = responceData.latitude.floatValue;
            _geoLocData.longitude = responceData.longitude.floatValue;
            
            if (!_geoLocData.placeMark) {
                
                if (!_rusLocaleLock || [loc.localeIdentifier isEqualToString:@"ru_RU"] ) {
                    CLLocation *loc = [[CLLocation alloc] initWithLatitude:_geoLocData.latitude  longitude:_geoLocData.longitude];
                    [geoCoder reverseGeocodeLocation:loc completionHandler:^(NSArray *placemarks, NSError *error) {
                        NSLog(@"Found placemarks: %@, error: %@", placemarks, error);
                        if (error == nil && [placemarks count] > 0) {
                            CLPlacemark *placemark = [placemarks lastObject];
                            
                            NSLog(@"placemark: subThoroughfare - %@/n thoroughfare - %@/n postalCode - %@/n locality - %@/n administrativeArea - %@/n country - %@/n",placemark.subAdministrativeArea, placemark.thoroughfare, placemark.postalCode, placemark.locality, placemark.administrativeArea, placemark.country);
                            [_geoLocData setPlaceMark:placemark];
                            if (selfCaptured.geoSuccess){
                                
                                if ([self checkPreferredLanguageLock]) {
                                    self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude, _geoLocData.country,_geoLocData.city, [self deleteRusStreet:_geoLocData.street], _geoLocData.house);
                                }
                                else {
                                    self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude,responceData.cityAdm,responceData.cityAdm, @"", @"");
                                }
                            }
                            
                            
                        } else {
                            NSLog(@"%@", error.debugDescription);
                        }
                    } ];

                }else{
                    self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude,responceData.cityAdm,responceData.cityAdm, @"", @"");
                }
                
                
            }
           
        }
        else{
            if (selfCaptured.geoSuccess && _geoLocData){
                
                                
                if ([self checkPreferredLanguageLock]) {
                    self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude, _geoLocData.country,_geoLocData.city, [self deleteRusStreet:_geoLocData.street], _geoLocData.house);
                }
                else {
                    self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude,responceData.cityAdm,responceData.cityAdm, @"", @"");
                }
                
               
            }
            
        }

        [selfCaptured saveCustomObject:_geoLocData];

    } failure:^(RKObjectRequestOperation *operation, NSError *error) {
        NSLog(@"FAIL!!!! - %@ ---------------------------%li",error, (long)error.code);
        
        
        if (!_geoLocData) {
            _geoLocData = [selfCaptured loadCustomObjectWithKey:@"geoData"];
            
            if (!_geoLocData) {
                self.geoFailure(error);
            }
            else{
                if (selfCaptured.geoSuccess){
                    
                    if ([self checkPreferredLanguageLock]) {
                        self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude, _geoLocData.country,_geoLocData.city, [self deleteRusStreet:_geoLocData.street], _geoLocData.house);
                    }
                    else {
                        self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude,responceData.cityAdm,responceData.cityAdm, @"", @"");
                    }

                }
  
            }
        }
        else{
            if ([self checkPreferredLanguageLock]) {
                self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude, _geoLocData.country,_geoLocData.city, [self deleteRusStreet:_geoLocData.street], _geoLocData.house);
            }
            else {
                self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude,responceData.cityAdm,responceData.cityAdm, @"", @"");
            }
        }
    }];
}


#pragma mark address processing

- (NSString *)deleteRusStreet:(NSString *)rusStreetAddress{
    return [rusStreetAddress stringByReplacingOccurrencesOfString:@"улица " withString:@""];
}

#pragma mark life cicle

- (void)setRuLocaleLock:(BOOL)rusLocaleLock{
    _rusLocaleLock = rusLocaleLock;
}

- (GeoData *)getGeoData{
    return  _geoLocData;
}

- (NSString *)getNearbyCity{
    return @"";
}

- (NSString *)getNearbyStreet{
    return @"";
}


- (BOOL)checkPreferredLanguageLock{
    
    NSString * language = [[NSLocale preferredLanguages] objectAtIndex:0];
    
    if ([language isEqualToString:@"ru"]) {
        return YES;
    }else if (_rusLocaleLock){
        return NO;
    }else
        return YES;
    
}

-(NSString *)returnPreferredLanguage { //as written text
    
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    NSArray *preferredLanguages = [defaults objectForKey:@"AppleLanguages"];
    NSString *preferredLanguageCode = [preferredLanguages objectAtIndex:0]; //preferred device language code
    NSLocale *enLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en"]; //language name will be in English (or whatever)
    NSString *languageName = [enLocale displayNameForKey:NSLocaleIdentifier value:preferredLanguageCode]; //name of language, eg. "French"
    return languageName;
    
}


#pragma mark saveToMemory

- (void)saveCustomObject:(GeoData *)obj {
    
    NSData *myEncodedObject = [NSKeyedArchiver archivedDataWithRootObject:obj];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:myEncodedObject forKey:@"geoData"];
    [defaults synchronize];
    
}

- (GeoData *)loadCustomObjectWithKey:(NSString *)key {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *myEncodedObject = [defaults objectForKey:key];
    GeoData *obj = (GeoData *)[NSKeyedUnarchiver unarchiveObjectWithData: myEncodedObject];
    return obj;
}

#pragma mark locationService delegate






- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    
    // If it's a relatively recent event, turn off updates to save power.

    GeoService *selfCaptured = self;
    CLLocation* location = [locations lastObject];
    NSDate* eventDate = location.timestamp;
    NSTimeInterval howRecent = [eventDate timeIntervalSinceNow];

    if (!_geoLocData) {
        _geoLocData = [[GeoData alloc] init];
    }
    _geoLocData.lastTime = eventDate;
    
    NSLocale *loc = [NSLocale currentLocale];
    
    if (!_rusLocaleLock || [loc.localeIdentifier isEqualToString:@"ru_RU"] ) {
        if (abs(howRecent) < 15.0) {
            _geoLocData.latitude = location.coordinate.latitude;
            _geoLocData.longitude = location.coordinate.longitude;
            [geoCoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
                NSLog(@"Found placemarks: %@, error: %@", placemarks, error);
                if (error == nil && [placemarks count] > 0) {
                    CLPlacemark *placemark = [placemarks lastObject];
                    if (!isTacking) {
                        [_locationManager stopUpdatingLocation];
                    }
                    NSLog(@"placemark: subThoroughfare - %@/n thoroughfare - %@/n postalCode - %@/n locality - %@/n administrativeArea - %@/n country - %@/n",placemark.subAdministrativeArea, placemark.thoroughfare, placemark.postalCode, placemark.locality, placemark.administrativeArea, placemark.country);
                    
                    [_geoLocData setPlaceMark:placemark];
                    
                     self.geoSuccess(_geoLocData.latitude, _geoLocData.longitude, _geoLocData.country,_geoLocData.city, [self deleteRusStreet:_geoLocData.street], _geoLocData.house);
                    
                    //[selfCaptured sendGeoReuestWithLatitude:location.coordinate.latitude andLongitude:location.coordinate.longitude];
                    
                } else {
                    NSLog(@"%@", error.debugDescription);
                    
                    [self sendGeoReuestWithLatitude:_geoLocData.latitude andLongitude:location.coordinate.longitude];
                }
            } ];
        }
    }else{
         [self sendGeoReuestWithLatitude:_geoLocData.latitude andLongitude:location.coordinate.longitude];
    }
}


- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error{
    NSLog(@"ERROR - %@",error.description);
    if (!isTacking) {
        [_locationManager stopUpdatingLocation];
    }
    
    NSDictionary *errorParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSString stringWithFormat:@"%@",[[NSLocale preferredLanguages] objectAtIndex:0]], @"device_language",
                                 [NSString stringWithFormat:@"%@",error], @"error_description",
                                 [NSString stringWithFormat:@"%li",(long)error.code], @"error_code",
                                 nil];
    [Flurry logEvent:@"get_user_location_fail" withParameters:errorParams];
    
    [self sendGeoReuestWithLatitude:0.0f andLongitude:0.0f];
    
}

#pragma mark Mapping

+ (NSDictionary *)getKeyPathsToXmlAttributesRelation{
    
    return  @{@"_version":@"version"};
    
}

+ (RKObjectMapping *)getObjectMapping{
    
    RKObjectMapping *mapping =  [RKObjectMapping mappingForClass:[GeoService class]];
    [mapping addAttributeMappingsFromDictionary: [GeoService  getKeyPathsToXmlAttributesRelation]];
    
    
    [mapping addPropertyMapping:[RKRelationshipMapping relationshipMappingFromKeyPath:@"response" toKeyPath:@"responses" withMapping:[GeoResponseData getObjectMapping]]];
    return mapping;
}

- (void)reverseGeoCodingWithCity:(NSString *)address andFinishBlock:(void (^)(CLLocation *))finishBlock{
    
   __block CLLocation *loc;
    
    NSString *sendAddress = address;
    
    [geoCoder geocodeAddressString:sendAddress
     
                 completionHandler:^(NSArray* placemarks, NSError* error){
                     
                     BOOL found = NO;
                     
                     for (CLPlacemark* aPlacemark in placemarks)
                         
                     {
                         if (aPlacemark.location && !found) {
                             loc = aPlacemark.location;
                             found = YES;
                         }
                       
                     }
                     if (loc) {
                         finishBlock(loc);
                     }else{
                         finishBlock(nil);
                     }
                     
                 }];
    
}

@end
