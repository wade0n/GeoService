//
//  GeoService.h
//  MyHome
//
//  Created by Дмитрий Калашников on 10/28/13.
//
//

#import <Foundation/Foundation.h>
#import <RestKit/RestKit.h>
#import <CoreLocation/CoreLocation.h>
#import "GeoData.h"
#import "GeoResponseData.h"

@interface GeoService : NSObject <CLLocationManagerDelegate>{
    RKObjectManager *networkEngine;
    CLLocationManager *_locationManager;
    CLGeocoder *geoCoder;
    GeoData *_geoLocData;
    GeoResponseData *responceData;
    BOOL isTacking;
    
    BOOL _rusLocaleLock;
}
@property(nonatomic, strong) NSArray *responses;
@property(nonatomic, strong) NSString *version;
@property(nonatomic, copy) void (^geoSuccess)(float latitude, float longtitude, NSString *countryStr, NSString *cityStr, NSString *streetStr, NSString *houseStr);
@property(nonatomic, copy) void (^geoFailure)(NSError *error);




+(id)sharedGeoService;

- (void)getGeoCoordinatesIfSuccess:(void (^)(float latitude, float longtitude, NSString *countryStr, NSString *cityStr, NSString *streetStr, NSString *houseStr))success
                           failure:(void (^)(NSError *error))failure;

- (void)startGeoTracking;
- (void)stopGeoTracking;
- (NSString *)getNearbyCity;
- (NSString *)getNearbyStreet;
- (void)reverseGeoCodingWithCity:(NSString *)address andFinishBlock:(void (^)(CLLocation *))finishBlock;
- (void)refresh;
// set to yes if you want to receive address only in russian
- (void)setRuLocaleLock:(BOOL)rusLocaleLock;
@end
