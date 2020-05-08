//
//  PrintImageBleWriteDelegate.m
//  RNBluetoothEscposPrinter
//
//  Created by januslo on 2018/10/8.
//  Copyright © 2018年 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PrintImageBleWriteDelegate.h"
@implementation PrintImageBleWriteDelegate


- (void) didWriteDataToBle: (BOOL)success {
    if(success){
        if (_now == -1) {
             if(_pendingResolve) {_pendingResolve(nil); _pendingResolve=nil;}
        } else if(_now >= [_toPrint length]) {
//            ASCII ESC M 0 CR LF
//            Hex 1B 4D 0 0D 0A
//            Decimal 27 77 0 13 10
            unsigned char * initPrinter = malloc(5);
            initPrinter[0]=27;
            initPrinter[1]=77;
            initPrinter[2]=0;
            initPrinter[3]=13;
            initPrinter[4]=10;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01f)), dispatch_get_main_queue(), ^{
                [RNBluetoothManager writeValue:[NSData dataWithBytes:initPrinter length:5] withDelegate:self];
                self.now = -1;
            });
        } else {
            [self print];
        }
    } else if (_pendingReject) {
        _pendingReject(@"PRINT_IMAGE_FAILED",@"PRINT_IMAGE_FAILED",nil);
        _pendingReject = nil;
    }
}

-(void) print {
    @synchronized (self) {
        NSInteger sizePerLine = (int)(_width/8);
        NSData *subData = [_toPrint subdataWithRange:NSMakeRange(_now, MIN(sizePerLine, (_toPrint.length - _now)))];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01f)), dispatch_get_main_queue(), ^{
            [RNBluetoothManager writeValue:subData withDelegate:self];
            self.now = self.now + sizePerLine;
        });
    }
}
@end
