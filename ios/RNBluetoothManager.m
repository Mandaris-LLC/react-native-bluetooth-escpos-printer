//
//  RNBluethManager.m
//  RNBluetoothEscposPrinter
//
//  Created by januslo on 2018/9/28.
//  Copyright © 2018年 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RNBluetoothManager.h"
#import <CoreBluetooth/CoreBluetooth.h>

@implementation RNBluetoothManager

NSString *EVENT_DEVICE_ALREADY_PAIRED = @"EVENT_DEVICE_ALREADY_PAIRED";
NSString *EVENT_DEVICE_DISCOVER_DONE = @"EVENT_DEVICE_DISCOVER_DONE";
NSString *EVENT_DEVICE_FOUND = @"EVENT_DEVICE_FOUND";
NSString *EVENT_CONNECTION_LOST = @"EVENT_CONNECTION_LOST";
NSString *EVENT_UNABLE_CONNECT=@"EVENT_UNABLE_CONNECT";
NSString *EVENT_CONNECTED=@"EVENT_CONNECTED";
NSString *EVENT_READY=@"EVENT_READY";

static NSArray<CBUUID *> *supportServices = nil;
static NSDictionary *writeableCharactiscs = nil;
bool hasListeners;
static CBPeripheral *connected;
static RNBluetoothManager<CBPeripheralDelegate> *instance;
static NSObject<WriteDataToBleDelegate> *writeDataDelegate;// delegate of write data resule;
static NSData *toWrite;
static NSTimer *timer;

+(Boolean)isConnected{
    return !(connected==nil);
}

+(void)writeValue:(NSData *) data withDelegate:(NSObject<WriteDataToBleDelegate> *) delegate
{
    @try{
        writeDataDelegate = delegate;
        toWrite = data;
        connected.delegate = instance;
        [connected discoverServices:supportServices];
//    [connected writeValue:data forCharacteristic:[writeableCharactiscs objectForKey:supportServices[0]] type:CBCharacteristicWriteWithoutResponse];
    }
    @catch(NSException *e){
        NSLog(@"error in writing data to %@,issue:%@",connected,e);
        [writeDataDelegate didWriteDataToBle:false];
    }
}

// Will be called when this module's first listener is added.
-(void)startObserving {
    hasListeners = YES;
    // Set up any upstream listeners or background tasks as necessary
}

// Will be called when this module's last listener is removed, or on dealloc.
-(void)stopObserving {
    hasListeners = NO;
    // Remove upstream listeners, stop unnecessary background tasks
}

/**
 * Exports the constants to javascritp.
 **/
- (NSDictionary *)constantsToExport
{
    
    /*
     EVENT_DEVICE_ALREADY_PAIRED    Emits the devices array already paired
     EVENT_DEVICE_DISCOVER_DONE    Emits when the scan done
     EVENT_DEVICE_FOUND    Emits when device found during scan
     EVENT_CONNECTION_LOST    Emits when device connection lost
     EVENT_UNABLE_CONNECT    Emits when error occurs while trying to connect device
     EVENT_CONNECTED    Emits when device connected
     */

    return @{ EVENT_DEVICE_ALREADY_PAIRED: EVENT_DEVICE_ALREADY_PAIRED,
              EVENT_DEVICE_DISCOVER_DONE:EVENT_DEVICE_DISCOVER_DONE,
              EVENT_DEVICE_FOUND:EVENT_DEVICE_FOUND,
              EVENT_CONNECTION_LOST:EVENT_CONNECTION_LOST,
              EVENT_UNABLE_CONNECT:EVENT_UNABLE_CONNECT,
              EVENT_CONNECTED:EVENT_CONNECTED,
              EVENT_READY:EVENT_READY
              };
}
- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

/**
 * Defines the event would be emited.
 **/
- (NSArray<NSString *> *)supportedEvents
{
    return @[EVENT_DEVICE_DISCOVER_DONE,
             EVENT_DEVICE_FOUND,
             EVENT_UNABLE_CONNECT,
             EVENT_CONNECTION_LOST,
             EVENT_CONNECTED,
             EVENT_DEVICE_ALREADY_PAIRED,
             EVENT_READY];
}


- (BOOL)isStateReady:(CBManagerState)state {
    return state == CBManagerStatePoweredOn;
}

RCT_EXPORT_MODULE(BluetoothManager);


- (CBCentralManager *) centralManager
{
    @synchronized(_centralManager)
    {
        if (!_centralManager)
        {
            if (![CBCentralManager instancesRespondToSelector:@selector(initWithDelegate:queue:options:)])
            {
                //for ios version lowser than 7.0
                self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
            }else
            {
                self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options: nil];
            }
        }
        if(!instance){
            instance = self;
        }
    }
    [self initSupportServices];
    return _centralManager;
}

//isBluetoothEnabled
RCT_EXPORT_METHOD(isBluetoothEnabled:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    CBManagerState state = [self.centralManager state];
    resolve([NSNumber numberWithBool:[self isStateReady:state]]);
}

//enableBluetooth
RCT_EXPORT_METHOD(enableBluetooth:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [self centralManager];
    resolve(nil);
}
//disableBluetooth
RCT_EXPORT_METHOD(disableBluetooth:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve(nil);
}
//scanDevices
RCT_EXPORT_METHOD(scanDevices:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    @try{
        if (!self.centralManager || ![self isStateReady:self.centralManager.state]) {
            reject(@"BLUETOOTCH_INVALID_STATE",@"BLUETOOTCH_INVALID_STATE",nil);
            return;
        }
        if(self.centralManager.isScanning){
            [self.centralManager stopScan];
        }
        self.scanResolveBlock = resolve;
        self.scanRejectBlock = reject;
        if (connected && connected.identifier) {
            NSDictionary *peripheralStored = @{connected.identifier.UUIDString: connected};
            if(!self.foundDevices){
                self.foundDevices = [[NSMutableDictionary alloc] init];
            }
            [self.foundDevices addEntriesFromDictionary:peripheralStored];
            [self sendDevicesFound];
        }
        [self initSupportServices];
        [self.centralManager scanForPeripheralsWithServices:supportServices options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@NO}];
        NSLog(@"Scanning started with services.");
        if(timer && timer.isValid){
            [timer invalidate];
            timer = nil;
        }
        timer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(callStop) userInfo:nil repeats:NO];
    
    }
    @catch(NSException *exception){
        NSLog(@"ERROR IN STARTING SCANE %@",exception);
        reject([exception name],[exception name],nil);
    }
}

//stop scan
RCT_EXPORT_METHOD(stopScan:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [self callStop];
    resolve(nil);
}

RCT_EXPORT_METHOD(getConnectedPrinter:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve(connected ? @{@"id": connected.identifier.UUIDString, @"name": connected.name ?: @""} : nil);
}

//connect(address)
RCT_EXPORT_METHOD(connect:(NSString *)address
                  findEventsWithResolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"Trying to connect....%@",address);
    [self callStop];
    if(connected){
        NSString *connectedAddress =connected.identifier.UUIDString;
        if([address isEqualToString:connectedAddress]){
            resolve(nil);
            return;
        }else{
            [self.centralManager cancelPeripheralConnection:connected];
            //Callbacks:
            //entralManager:didDisconnectPeripheral:error:
        }
    }
    CBPeripheral *peripheral = [self.foundDevices objectForKey:address];
    self.connectResolveBlock = resolve;
    self.connectRejectBlock = reject;
    if(peripheral){
        _waitingConnect = address;
        NSLog(@"Trying to connectPeripheral....%@",address);
        [self.centralManager connectPeripheral:peripheral options:nil];
        // Callbacks:
        //    centralManager:didConnectPeripheral:
        //    centralManager:didFailToConnectPeripheral:error:
    }else{
        _waitingConnect = address;
        [self.centralManager scanForPeripheralsWithServices:supportServices options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@NO}];
    }
}

RCT_EXPORT_METHOD(unpair:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if(connected) {
        [self.centralManager cancelPeripheralConnection:connected];
    }
    resolve(nil);
}


-(void)callStop {
    if (self.centralManager.isScanning) {
        [self.centralManager stopScan];
        if(hasListeners){
            [self sendEventWithName:EVENT_DEVICE_DISCOVER_DONE body:nil];
        }
        if(self.scanResolveBlock){
            RCTPromiseResolveBlock rsBlock = self.scanResolveBlock;
            rsBlock(nil);
            self.scanResolveBlock = nil;
        }
    }
    if (timer && timer.isValid){
        [timer invalidate];
        timer = nil;
    }
    self.scanRejectBlock = nil;
    self.scanResolveBlock = nil;
}

- (void)initSupportServices {
    if(!supportServices){
        CBUUID *issc = [CBUUID UUIDWithString: @"E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"];
        supportServices = [NSArray arrayWithObject:issc];/*ISSC*/
        writeableCharactiscs = @{issc:@"BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F"};
    }
}

- (void)sendDevicesFound {
    NSMutableArray *devices = [[NSMutableArray alloc] init];
    [self.foundDevices enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, CBPeripheral * _Nonnull obj, BOOL * _Nonnull stop) {
        [devices addObject:@{@"id":obj.identifier.UUIDString, @"name" : obj.name ?: @""}];
    }];
    if(hasListeners){
        [self sendEventWithName:EVENT_DEVICE_FOUND body:devices];
    }
}

/**
 * CBCentralManagerDelegate
 **/
- (void)centralManagerDidUpdateState:(CBCentralManager *)central{
    if ([self isStateReady:central.state]) {
        if(hasListeners){
            [self sendEventWithName:EVENT_READY body:nil];
        }
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *, id> *)advertisementData RSSI:(NSNumber *)RSSI{
    NSLog(@"did discover peripheral: %@", peripheral);
    NSDictionary *peripheralStored = @{peripheral.identifier.UUIDString: peripheral};
    if (!self.foundDevices) {
        self.foundDevices = [[NSMutableDictionary alloc] init];
    }
    [self.foundDevices addEntriesFromDictionary:peripheralStored];
    if(_waitingConnect && [_waitingConnect isEqualToString: peripheral.identifier.UUIDString]){
        [self.centralManager connectPeripheral:peripheral options:nil];
        [self callStop];
    } else {
        [self sendDevicesFound];
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral{
    NSLog(@"did connected: %@",peripheral);
    connected = peripheral;
    NSString *pId = peripheral.identifier.UUIDString;
    if(_waitingConnect && [_waitingConnect isEqualToString: pId] && self.connectResolveBlock) {
        self.connectResolveBlock(nil);
        _waitingConnect = nil;
        self.connectRejectBlock = nil;
        self.connectResolveBlock = nil;
    }
    if(hasListeners) {
        [self sendEventWithName:EVENT_CONNECTED body:@{@"name":peripheral.name?peripheral.name:@"",@"id":peripheral.identifier.UUIDString}];
    }
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(nullable NSError *)error{
    if(!connected && _waitingConnect && [_waitingConnect isEqualToString:peripheral.identifier.UUIDString]) {
        if(self.connectRejectBlock) {
            RCTPromiseRejectBlock rjBlock = self.connectRejectBlock;
            rjBlock(@"",@"",error);
            self.connectRejectBlock = nil;
            self.connectResolveBlock = nil;
            _waitingConnect=nil;
        }
        connected = nil;
        if(hasListeners) {
            [self sendEventWithName:EVENT_UNABLE_CONNECT body:@{@"name":peripheral.name?peripheral.name:@"",@"address":peripheral.identifier.UUIDString}];
        }
    } else {
        connected = nil;
        if(hasListeners) {
            [self sendEventWithName:EVENT_CONNECTION_LOST body:nil];
        }
    }
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(nullable NSError *)error{
    if (self.connectRejectBlock) {
        RCTPromiseRejectBlock rjBlock = self.connectRejectBlock;
        rjBlock(@"",@"",error);
        self.connectRejectBlock = nil;
        self.connectResolveBlock = nil;
        _waitingConnect = nil;
    }
    connected = nil;
    if(hasListeners) {
        [self sendEventWithName:EVENT_UNABLE_CONNECT body:@{@"name":peripheral.name?peripheral.name:@"",@"address":peripheral.identifier.UUIDString}];
    }
}

/**
 * END OF CBCentralManagerDelegate
 **/

/*!
 *  @method peripheral:didDiscoverServices:
 *
 *  @param peripheral    The peripheral providing this information.
 *    @param error        If an error occurred, the cause of the failure.
 *
 *  @discussion            This method returns the result of a @link discoverServices: @/link call. If the service(s) were read successfully, they can be retrieved via
 *                        <i>peripheral</i>'s @link services @/link property.
 *
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(nullable NSError *)error{
    if (error){
        return;
    }
    for (CBService *service in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:service];
         NSLog(@"服务id：%@",service.UUID.UUIDString);
    }
    
    if(error && self.connectRejectBlock){
        RCTPromiseRejectBlock rjBlock = self.connectRejectBlock;
         rjBlock(@"",@"",error);
        self.connectRejectBlock = nil;
        self.connectResolveBlock = nil;
        connected = nil;
    }else
    if(_waitingConnect && _waitingConnect == peripheral.identifier.UUIDString){
        RCTPromiseResolveBlock rsBlock = self.connectResolveBlock;
        rsBlock(peripheral.identifier.UUIDString);
        self.connectRejectBlock = nil;
        self.connectResolveBlock = nil;
        connected = peripheral;
    }
}

/*!
 *  @method peripheral:didDiscoverCharacteristicsForService:error:
 *
 *  @param peripheral    The peripheral providing this information.
 *  @param service        The <code>CBService</code> object containing the characteristic(s).
 *    @param error        If an error occurred, the cause of the failure.
 *
 *  @discussion            This method returns the result of a @link discoverCharacteristics:forService: @/link call. If the characteristic(s) were read successfully,
 *                        they can be retrieved via <i>service</i>'s <code>characteristics</code> property.
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(nullable NSError *)error{
    if(toWrite && connected
       && [connected.identifier.UUIDString isEqualToString:peripheral.identifier.UUIDString]
       && [service.UUID.UUIDString isEqualToString:supportServices[0].UUIDString]){
        if(error){
            NSLog(@"Discrover charactoreristics error:%@",error);
           if(writeDataDelegate)
           {
               [writeDataDelegate didWriteDataToBle:false];
               return;
           }
        }
        for(CBCharacteristic *cc in service.characteristics){
            NSLog(@"Characterstic found: %@ in service: %@" ,cc,service.UUID.UUIDString);
            if([cc.UUID.UUIDString isEqualToString:[writeableCharactiscs objectForKey: supportServices[0]]]){
                @try{
                    [connected writeValue:toWrite forCharacteristic:cc type:CBCharacteristicWriteWithoutResponse];
                   if(writeDataDelegate) [writeDataDelegate didWriteDataToBle:true];
                    if(toWrite){
                        NSLog(@"Value wrote: %lu",[toWrite length]);
                    }
                }
                @catch(NSException *e){
                    NSLog(@"ERRO IN WRITE VALUE: %@",e);
                      [writeDataDelegate didWriteDataToBle:false];
                }
            }
        }
    }
    if(error){
        NSLog(@"Discrover charactoreristics error:%@",error);
        return;
    }
}

/*!
 *  @method peripheral:didWriteValueForCharacteristic:error:
 *
 *  @param peripheral        The peripheral providing this information.
 *  @param characteristic    A <code>CBCharacteristic</code> object.
 *    @param error            If an error occurred, the cause of the failure.
 *
 *  @discussion                This method returns the result of a {@link writeValue:forCharacteristic:type:} call, when the <code>CBCharacteristicWriteWithResponse</code> type is used.
 */
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(nullable NSError *)error{
    if(error){
        NSLog(@"Error in writing bluetooth: %@",error);
        if(writeDataDelegate){
            [writeDataDelegate didWriteDataToBle:false];
        }
    }
    
    NSLog(@"Write bluetooth success.");
    if(writeDataDelegate){
        [writeDataDelegate didWriteDataToBle:true];
    }
}
 
@end
