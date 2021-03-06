//
//  TSSManager.mm
//  TSSAgent
//
//  Created by Kevin Bradley on 1/16/12.
//  Copyright 2012 nito, LLC. All rights reserved.
//

//#import "MSettingsController.h"

#import "TSSManager.h"
#import "IOKit/IOKitLib.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <sys/types.h>
#import "TSSCommon.h"


/*
 
 all of this asynchronous stuff isn't really needed anymore, im just too lazy to prune it out. *SHOCK*
 
 
 */

@interface TSSManager ()

	// Properties that don't need to be seen by the outside world.

@property (nonatomic, readonly) BOOL              isReceiving;
@property (nonatomic, retain)   NSURLConnection * connection;

@end


static NSString *ChipID_ = nil;

static NSString *HexToDec(NSString *hexValue)
{
	if (hexValue == nil)
		return nil;
	
	unsigned long long dec;
	NSScanner *scan = [NSScanner scannerWithString:hexValue];
	if ([scan scanHexLongLong:&dec])
	{
		
		return [NSString stringWithFormat:@"%llu", dec];
		//NSLog(@"chipID binary: %@", finalValue);
	}
	
	return nil;
}

/*
 
 CYDIOGetValue is a carbon copy of CYIOGetValue from Cydia by Jay Freeman
 CYDHex is a carbon copy of CYDHex from Cydia by Jay Freeman
 */

static NSObject *CYDIOGetValue(const char *path, NSString *property) {
	
    io_registry_entry_t entry(IORegistryEntryFromPath(kIOMasterPortDefault, path));
    if (entry == MACH_PORT_NULL)
        return nil;
	
    CFTypeRef value(IORegistryEntryCreateCFProperty(entry, (CFStringRef) property, kCFAllocatorDefault, 0));
    IOObjectRelease(entry);
	
    if (value == NULL)
        return nil;
    return [(id) value autorelease];
}

static NSString *CYDHex(NSData *data, bool reverse) {
    if (data == nil)
        return nil;
	
    size_t length([data length]);
    uint8_t bytes[length];
    [data getBytes:bytes];
	
    char string[length * 2 + 1];
    for (size_t i(0); i != length; ++i)
        sprintf(string + i * 2, "%.2x", bytes[reverse ? length - i - 1 : i]);
	
    return [NSString stringWithUTF8String:string];
}

@implementation TSSManager

@synthesize baseUrlString, delegate, _returnDataAsString, ecid, mode, theDevice;

/*
 
 [{"model": "AppleTV2,1", "chip": 35120, "firmware": "4.2", "board": 16, "build": "8C150"}, {"model": "AppleTV2,1", "chip": 35120, "firmware": "4.2.1", "board": 16, "build": "8C154"}, {"model": "AppleTV2,1", "chip": 35120, "firmware": "4.3", "board": 16, "build": "8F191m"}, {"model": "AppleTV2,1", "chip": 35120, "firmware": "4.3.1", "board": 16, "build": "8F202"}, {"model": "AppleTV2,1", "chip": 35120, "firmware": "4.3~b1", "board": 16, "build": "8F5148c"}, {"model": "AppleTV2,1", "chip": 35120, "firmware": "4.3~b2", "board": 16, "build": "8F5153d"}, {"model": "AppleTV2,1", "chip": 35120, "firmware": "4.3~b3", "board": 16, "build": "8F5166b"}, {"model": "AppleTV2,1", "chip": 35120, "firmware": "4.1", "board": 16, "build": "8M89"}, {"model": "AppleTV2,1", "chip": 35120, "firmware": null, "board": 16, "build": "9A406a"}]
 
 
 1. separate by "}," (then remove [{)
 
 [{"model": "AppleTV2,1", "chip": 35120, "firmware": "4.2", "board": 16, "build": "8C150"
 
 2. separate by ", "
 
 "model": "AppleTV2,1"
 
 3. separate by :
 
 "model"
 
 4. set object 1 of array3 as key
 
 5. add final dictionary to full array
 
 6. return
 
 
 */

+ (NSArray *)blobArrayFromString:(NSString *)theString
{
	if ([[theString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:@"[]"])
	{
		return nil;
	}
	NSMutableString *stripped = [[NSMutableString alloc] initWithString:theString];
	[stripped replaceOccurrencesOfString:@"[" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [stripped length])];
	[stripped replaceOccurrencesOfString:@"{" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [stripped length])];
	[stripped replaceOccurrencesOfString:@"\"" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [stripped length])];
	
	NSMutableArray *blobArray = [[NSMutableArray alloc] init];
	
	NSArray *fullArray = [stripped componentsSeparatedByString:@"},"]; //1.
	for (id currentBlob in fullArray)
	{ 
		NSArray *keyItems = [currentBlob componentsSeparatedByString:@", "]; //2.
		NSMutableDictionary *theDict = [[NSMutableDictionary alloc] init];
		for (id currentKey in keyItems)
		{
			NSArray *keyObjectArray = [[currentKey stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"}]"]] componentsSeparatedByString:@":"]; //3.
			NSString *theObject = [[keyObjectArray objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			NSString *theKey = [[keyObjectArray objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];			
			[theDict setObject:theObject forKey:theKey];	//4.		
		}
		
		[blobArray addObject:[theDict autorelease]]; //5.
		
	}
	[stripped release];
	stripped = nil;
	return [blobArray autorelease];
	
}

+ (NSString *)versionFromBuild:(NSString *)buildNumber
{
	if ([buildNumber isEqualToString:@"8F455"])
		return @"4.3";
	if ([buildNumber isEqualToString:@"9A334v"])
		return @"4.4";
	if ([buildNumber isEqualToString:@"9A335a"])
		return @"4.4.1";
	if ([buildNumber isEqualToString:@"9A336a"])
		return @"4.4.2";
	if ([buildNumber isEqualToString:@"9A405l"])
		return @"4.4.3";
	if ([buildNumber isEqualToString:@"9A406a"])
		return @"4.4.4";
	if ([buildNumber isEqualToString:@"9B5127c"])
		return @"5.0b1";
	if ([buildNumber isEqualToString:@"9B5141a"])
		return @"5.0b2";
}

- (void)logDevice:(TSSDeviceID)inputDevice
{
	NSLog(@"TSSDeviceID(boardID: %i, chipID: %i)", inputDevice.boardID, inputDevice.chipID);
}

+ (TSSDeviceID)currentDevice
{
	NSString *rawDevice = [TSSCommon stringReturnForProcess:@"/usr/sbin/sysctl -n hw.machine"];
	NSString *theDevice = [rawDevice stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	//NSLog(@"theDevice: -%@-", theDevice);
	
	if ([theDevice isEqualToString:@"AppleTV2,1"])
		return DeviceIDMake(16, 35120);
	
	if ([theDevice isEqualToString:@"iPad1,1"])
		return DeviceIDMake(2, 35120);
		
	if ([theDevice isEqualToString:@"iPad2,1"])
		return DeviceIDMake(4, 35136);

	if ([theDevice isEqualToString:@"iPad2,2"])
		return DeviceIDMake(6, 35136);
	
	if ([theDevice isEqualToString:@"iPad2,3"])
		return DeviceIDMake(2, 35136);
	
	if ([theDevice isEqualToString:@"iPad2,1"])
		return DeviceIDMake(4, 35136);
	
	if ([theDevice isEqualToString:@"iPhone1,1"])
		return DeviceIDMake(0, 35072);
	
	if ([theDevice isEqualToString:@"iPhone1,2"])
		return DeviceIDMake(4, 35072);
	
	if ([theDevice isEqualToString:@"iPhone2,1"])
		return DeviceIDMake(0, 35104);
	
	if ([theDevice isEqualToString:@"iPhone3,1"])
		return DeviceIDMake(0, 35120);
	
	if ([theDevice isEqualToString:@"iPhone3,3"])
		return DeviceIDMake(6, 35120);
	
	if ([theDevice isEqualToString:@"iPod1,1"])
		return DeviceIDMake(2, 35072);
	
	if ([theDevice isEqualToString:@"iPod2,1"])
		return DeviceIDMake(0, 34592);

	if ([theDevice isEqualToString:@"iPod3,1"])
		return DeviceIDMake(2, 35106);
	
	if ([theDevice isEqualToString:@"iPod4,1"])
		return DeviceIDMake(8, 35120);
	
	return TSSNullDevice;
	
	/*
	 

	 "appletv2,1": (35120, 16, 'AppleTV2,1'),
	 
	 "ipad1,1": (35120, 2, 'iPad1,1'),
	 "ipad2,1": (35136, 4, 'iPad2,1'),
	 "ipad2,2": (35136, 6, 'iPad2,2'),
	 "ipad2,3": (35136, 2, 'iPad2,3'),
	 
	 "iphone1,1": (35072, 0, 'iPhone1,1'),
	 "iphone1,2": (35072, 4, 'iPhone1,2'),
	 "iphone2,1": (35104, 0, 'iPhone2,1'),
	 "iphone3,1": (35120, 0, 'iPhone3,1'),
	 "iphone3,3": (35120, 6, 'iPhone3,3'),
	 
	 "ipod1,1": (35072, 2, 'iPod1,1'),
	 "ipod2,1": (34592, 0, 'iPod2,1'),
	 "ipod3,1": (35106, 2, 'iPod3,1'),
	 "ipod4,1": (35120, 8, 'iPod3,1'),
	 
	 */
}

+ (NSString *)rawBlobFromResponse:(NSString *)inputString
{

	NSArray *componentArray = [inputString componentsSeparatedByString:@"&"];
	int count = [componentArray count];
//	int status = [[[[componentArray objectAtIndex:0] componentsSeparatedByString:@"="] lastObject] intValue];
//	NSString *message = [[[componentArray objectAtIndex:1] componentsSeparatedByString:@"="] lastObject];
	if (count >= 3)
	{
		NSString *plist = [[componentArray objectAtIndex:2] substringFromIndex:15];
		return plist;
	} else {
		
		NSLog(@"probably failed: %@ count: %i", componentArray, count);
		
		return nil;
	}
	
	
}

//deprecated

+ (NSString *)blobPathFromString:(NSString *)inputString andEcid:(NSString *)theEcid andBuild:(NSString *)theBuildVersion
{
	//LOG_SELF
		//STATUS=0&MESSAGE=SUCCESS&REQUEST_STRING=<?xml
	
	NSString *version = [TSSManager versionFromBuild:theBuildVersion];
	//NSLog(@"version: %@", version);
	NSArray *componentArray = [inputString componentsSeparatedByString:@"&"];
		//	NSLog(@"componentArray: %@", componentArray);
	int count = [componentArray count];
		//STATUS=0
		//MESSAGE=SUCCESS
		//REQUEST_STRING=<?xml
		
		//int status = [[[[componentArray objectAtIndex:0] componentsSeparatedByString:@"="] lastObject] intValue];
		//NSString *message = [[[componentArray objectAtIndex:1] componentsSeparatedByString:@"="] lastObject];
	if (count >= 3)
	{
		NSString *plist = [[componentArray objectAtIndex:2] substringFromIndex:15];
			//NSLog(@"plist: %@", plist);
		
		NSString *outputName = [NSString stringWithFormat:@"/private/var/tmp/%@-appletv2,1-%@", theEcid, version];
		//NSLog(@"outputName: %@", outputName);
			//NSString *finalName = [outputName stringByAppendingPathExtension:@"shsh"];
			//NSString *tmp = @"/private/var/tmp/thefile";
		[plist writeToFile:outputName atomically:YES encoding:NSUTF8StringEncoding error:nil];
			//NSDictionary *blob = [NSDictionary dictionaryWithContentsOfFile:outputName];
			//[[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
			//gzip 780309390798-appletv2,1-4.4 -S.shsh
			//[self gzipBlob:outputName];
		
		return outputName;
	} else {
		
		NSLog(@"probably failed: %@ count: %i", componentArray, count);
		
		return nil;
	}
	
	
}

//deprecated

+ (NSString *)blobPathFromString:(NSString *)inputString andEcid:(NSString *)theEcid
{
		//STATUS=0&MESSAGE=SUCCESS&REQUEST_STRING=<?xml
	
	NSArray *componentArray = [inputString componentsSeparatedByString:@"&"];
		//	NSLog(@"componentArray: %@", componentArray);
	int count = [componentArray count];
		//STATUS=0
		//MESSAGE=SUCCESS
		//REQUEST_STRING=<?xml
	
		//int status = [[[[componentArray objectAtIndex:0] componentsSeparatedByString:@"="] lastObject] intValue];
		//NSString *message = [[[componentArray objectAtIndex:1] componentsSeparatedByString:@"="] lastObject];
	
	if (count >= 3)
	{
		NSString *plist = [[componentArray objectAtIndex:2] substringFromIndex:15];
			//NSLog(@"plist: %@", plist);
		
		NSString *outputName = [NSString stringWithFormat:@"/private/var/tmp/%@-appletv2,1-%@", theEcid, [TSSCommon osVersion]];
			//NSString *finalName = [outputName stringByAppendingPathExtension:@"shsh"];
			//NSString *tmp = @"/private/var/tmp/thefile";
		[plist writeToFile:outputName atomically:YES encoding:NSUTF8StringEncoding error:nil];
			//NSDictionary *blob = [NSDictionary dictionaryWithContentsOfFile:outputName];
			//[[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
			//gzip 780309390798-appletv2,1-4.4 -S.shsh
			//[self gzipBlob:outputName];
		
		return outputName;
	} else {
		
		NSLog(@"probably failed: %@ count: %i", componentArray, count);
		
		return nil;
	}
	
	
}

+(NSString *) ipAddress {
    NSString * h = [[[NSHost currentHost] addresses] objectAtIndex:1];
    return h ;  
}

	/* 
	 
	 the request we send to get the list of SHSH blobs for the current device 

	 NOTE: this is all requisite on saurik updating the BuildManifest info on his servers to reflect new versions.
*/


- (NSMutableURLRequest *)requestForList
{

	NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
	[request setURL:[NSURL URLWithString:baseUrlString]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"X-User-Agent" forHTTPHeaderField:@"User-Agent"];
	[request setValue:nil forHTTPHeaderField:@"X-User-Agent"];
	
	return request;
		//return request;
}

/*
 
 we call this request when we are trying to send the blob TO cydia after fetching it FROM apple
 
 */

- (NSMutableURLRequest *)oldrequestForBlob:(NSString *)theBlob
{
		//LOG_SELF
	NSString *post = [NSString stringWithContentsOfFile:theBlob encoding:NSUTF8StringEncoding error:nil];
	
		//	[[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
	//NSLog(@"post: %@", post);
	NSData *postData = [post dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
	
	NSString *postLength = [NSString stringWithFormat:@"%d", [postData length]];
	
	NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
	[request setURL:[NSURL URLWithString:baseUrlString]];
	[request setHTTPMethod:@"POST"];
	[request setValue:postLength forHTTPHeaderField:@"Content-Length"];
	[request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"X-User-Agent" forHTTPHeaderField:@"User-Agent"];
	[request setValue:nil forHTTPHeaderField:@"X-User-Agent"];
	[request setHTTPBody:postData];
	
	return request;

}

- (NSMutableURLRequest *)requestForBlob:(NSString *)post
{
	//LOG_SELF
	//NSString *post = [NSString stringWithContentsOfFile:theBlob encoding:NSUTF8StringEncoding error:nil];
	
	//	[[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
	//NSLog(@"post: %@", post);
	NSData *postData = [post dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
	
	NSString *postLength = [NSString stringWithFormat:@"%d", [postData length]];
	
	NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
	[request setURL:[NSURL URLWithString:baseUrlString]];
	[request setHTTPMethod:@"POST"];
	[request setValue:postLength forHTTPHeaderField:@"Content-Length"];
	[request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"X-User-Agent" forHTTPHeaderField:@"User-Agent"];
	[request setValue:nil forHTTPHeaderField:@"X-User-Agent"];
	[request setHTTPBody:postData];
	
	return request;
}


/*
 
 we use this to convert and NSDictionary (the dictionary we got from the initial string) into a string.
 
 */

- (NSString *)stringFromDictionary:(NSDictionary *)theDict
{
	NSString *error = nil;
	NSData *xmlData = [NSPropertyListSerialization dataFromPropertyList:theDict format:kCFPropertyListXMLFormat_v1_0 errorDescription:&error];
	NSString *s=[[NSString alloc] initWithData:xmlData encoding: NSUTF8StringEncoding];
	return [s autorelease];
}

/*
 
 the url request to fetch a particular version from apple for the SHSH blob
 
 */

- (NSMutableURLRequest *)postRequestFromVersion:(NSString *)theVersion
{
		//	LOG_SELF
		//NSString *tmp = @"/private/var/tmp/thefile";
	NSDictionary *theDict = [self tssDictFromVersion:theVersion]; //create a dict based on buildmanifest, we want to read this dictionary from a server in the future.
	self.ecid = [theDict valueForKey:@"ApECID"];
		//NSLog(@"self.ecid: %@", self.ecid);
	[ecid retain];
	
		//[theDict writeToFile:tmp atomically:YES];
		//NSString *post = [NSString stringWithContentsOfFile:tmp];

	NSString *post = [self stringFromDictionary:theDict]; //convert the nsdictionary into a string we can submit
	
		//[[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
		//NSLog(@"post: %@", post);
	NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES]; //this might actually need to be NSUTF8StringEncoding, but it works.
	
	NSString *postLength = [NSString stringWithFormat:@"%d", [postData length]];
	
	NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] init] autorelease];
	[request setURL:[NSURL URLWithString:baseUrlString]];
	[request setHTTPMethod:@"POST"];
	[request setValue:postLength forHTTPHeaderField:@"Content-Length"];
	[request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"InetURL/1.0" forHTTPHeaderField:@"User-Agent"];
	[request setHTTPBody:postData];
	
	return request;
	//return request;
}

+ (NSArray *)signableVersions
{
	NSDictionary *k66 = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:BLOB_PLIST_URL]];
	return [k66 valueForKey:@"openVersions"];
}

/*
 
 grabs the proper build manifest info from a local plist called k66ap.plist, in the future (for release) need to fetch from a plist onlinel.
 
 we combine this build manifest into an example dictionary (plist) to make a tss request from apples servers.
 
 
 */

- (NSDictionary *)tssDictFromVersion:(NSString *)versionNumber //ie 9A406a
{
	TSSDeviceID cd = self.theDevice;
	//[self logDevice:cd];
	
	NSDictionary *k66 = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:BLOB_PLIST_URL]];
		//NSDictionary *k66 = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle bundleForClass:[TSSManager class]] pathForResource:@"k66ap" ofType:@"plist"]];
	//NSLog(@"k66: %@", k66);
	NSDictionary *versionDict = [k66 valueForKey:versionNumber];
	
	NSMutableDictionary *theDict = [[NSMutableDictionary alloc] initWithDictionary:versionDict];
	
		//ChipID_ = HexToDec([CYDHex((NSData *) CYDIOGetValue("IODeviceTree:/chosen", @"unique-chip-id"), true) uppercaseString]);
	//NSString *SerialNumber_ = (NSString *) CYDIOGetValue("IOService:/", @"IOPlatformSerialNumber");
	//NSLog(@"chipID hex: %@", ChipID_);
	//NSLog(@"SerialNumber_: %@", SerialNumber_);
	//NSLog(@"chipID dec: %@", HexToDec(ChipID_));
	[theDict setObject:[NSNumber numberWithBool:YES] forKey:@"@APTicket"];
	[theDict setObject:[TSSManager ipAddress] forKey:@"@HostIpAddress"];
	[theDict setObject:@"mac" forKey:@"@HostPlatformInfo"];
	//[theDict setObject:[TSSManager uuidFormatted] forKey:@"@UUID"];
	[theDict setObject:[NSNumber numberWithInt:cd.boardID] forKey:@"ApBoardID"];
	[theDict setObject:[NSNumber numberWithInt:cd.chipID] forKey:@"ApChipID"];
	[theDict setObject:@"libauthinstall-107" forKey:@"@VersionInfo"];
	[theDict setObject:ChipID_ forKey:@"ApECID"];
	
	//FIXME: STILL NEED ApNonce?
	
	[theDict setObject:[NSNumber numberWithBool:YES] forKey:@"ApProductionMode"];
	[theDict setObject:[NSNumber numberWithInt:1] forKey:@"ApSecurityDomain"];
	
	return [theDict autorelease];
	
}

/*
 
 used to think the UUID listed in the tss-request was the uuid of the actual device, now i dont know what it is, dont know if its important.
 
 */
/*
+ (NSString *)uuidFormatted
{
	[TSSCommon fixUIDevices];
	NSString *theUUID = [[[UIDevice currentDevice] uniqueIdentifier] uppercaseString];
	//NSLog(@"ogUUID: %@", theUUID);
	NSString *stringOne = [theUUID substringWithRange:NSMakeRange(0, 8)];
	NSString *stringTwo = [theUUID substringWithRange:NSMakeRange(8, 4)];
	NSString *stringThree = [theUUID substringWithRange:NSMakeRange(12, 4)];
	NSString *stringFour = [theUUID substringWithRange:NSMakeRange(16, 4)];
	NSString *stringFive = [theUUID substringWithRange:NSMakeRange(20, [theUUID length] - 20)];
	
	return [NSString stringWithFormat:@"%@-%@-%@-%@-%@", stringOne, stringTwo, stringThree, stringFour, stringFive];
	
	
}
*/

/*
 
 should have a switch statement here to start the requisite processes, not just for the blob listing one, even if the delegate is set after its hould still pick up the end functions properly.
 
 
 */

- (id)initWithMode:(int)theMode
{
	if ((self = [super init]) != nil);
	{
		
			//NSDictionary *tssDict = [TSSManager tssDict];
			ChipID_ = HexToDec([CYDHex((NSData *) CYDIOGetValue("IODeviceTree:/chosen", @"unique-chip-id"), true) uppercaseString]);
			//ChipID_ = @"5551532";
			//NSLog(@"ECID: %@", ChipID_);
		
		theDevice = [TSSManager currentDevice];
			//NSLog(@"tssDict: %@", tssDict);
			//[self _startReceive];
		self.mode = theMode;
		
		if (theMode == kTSSCydiaBlobListing)
		{
			//NSLog(@"checkForBlobs");
			[self _checkForBlobs];
			
			
		}
			
		
		return (self);
		
	}
	
	return nil;
}


	//URL/receiving crap

	// not used yet

- (void)_receiveDidStart
{
	
	
}

- (void)_updateStatus:(int)status
{
	
}

- (void)_receiveDidStopWithStatus:(int)status
{
	
	if( delegate && [delegate respondsToSelector:@selector(processorDidFinish:withStatus:)] ) {
		[delegate processorDidFinish:self withStatus:status];
	}
	
}

#pragma mark * Core transfer code

	// This is the code that actually does the networking.

@synthesize connection    = _connection;


- (BOOL)isReceiving
{
    return (self.connection != nil);
}

- (NSArray *)_synchronousBlobCheck
{
	
		//just check if interwebz are available first, if they aren't, bail
	
	if ([TSSCommon internetAvailable] == FALSE)
	{
		
		NSLog(@"no internet available, should we bail?!");
			//	return nil
		
	}
	
    BOOL                success;
    NSURL *             url;
    NSMutableURLRequest *      request;
    
	// First get and check the URL.
    
	baseUrlString = [NSString stringWithFormat:@"http://cydia.saurik.com/tss@home/api/check/%@", ChipID_];
	
	//baseUrlString = @"http://cydia.saurik.com/TSS/controller?action=2";
	
	
	url = [NSURL URLWithString:baseUrlString];
	
    success = (url != nil);
	
	//NSLog(@"URL: %@", url);
	
	
	// If the URL is bogus, let the user know.  Otherwise kick off the connection.
    
    if ( ! success) {
		assert(!success);
		
    } else {
		
		
		// Open a connection for the URL.
		
        request = [self requestForList];
		
        assert(request != nil);
        
	
		NSURLResponse *theResponse = nil;
		NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:&theResponse error:nil];
		
		NSString *datString = [[NSString alloc] initWithData:returnData  encoding:NSUTF8StringEncoding];
		
			//NSLog(@"datString length: %i", [datString length]);
		
		if ([datString length] <= 2)
		{

			[datString release];
			return nil;
		}
		
		NSArray *blobArray = [TSSManager blobArrayFromString:datString]; 
		
		[datString release];
		
		return blobArray;
	
    }
	
	return nil;
}

- (void)_checkForBlobs
{
    BOOL                success;
    NSURL *             url;
    NSMutableURLRequest *      request;
    receivedData =		[[NSMutableData data] retain];
    assert(self.connection == nil);         // don't tap receive twice in a row!
	
	
		// First get and check the URL.
    
	baseUrlString = [NSString stringWithFormat:@"http://cydia.saurik.com/tss@home/api/check/%@", ChipID_];
	
		//baseUrlString = @"http://cydia.saurik.com/TSS/controller?action=2";
	
	
	url = [NSURL URLWithString:baseUrlString];
	
    success = (url != nil);
	
		//NSLog(@"URL: %@", url);
	
	
		// If the URL is bogus, let the user know.  Otherwise kick off the connection.
    
    if ( ! success) {
		assert(!success);
		
			//self.statusLabel.text = @"Invalid URL";
    } else {
		
		
			// Open a connection for the URL.
		
        request = [self requestForList];
			//[request setHTTPMethod:@"POST"];
		
        assert(request != nil);
        
        self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
        assert(self.connection != nil);
		
			// Tell the UI we're receiving.
        
        [self _receiveDidStart];
    }
}

- (void)_pushBlob:(NSString *)theBlob
{
    BOOL                success;
    NSURL *             url;
    NSMutableURLRequest *      request;
    receivedData =		[[NSMutableData data] retain];
    assert(self.connection == nil);         // don't tap receive twice in a row!
	
	TSSDeviceID cd = self.theDevice;
	
	//[self logDevice:cd];
		// First get and check the URL.
    
	//baseUrlString = [NSString stringWithFormat:@"http://cydia.saurik.com/tss@home/api/store/35120/16/%@", ChipID_];
	
	baseUrlString = [NSString stringWithFormat:@"http://cydia.saurik.com/tss@home/api/store/%i/%i/%@", cd.chipID, cd.boardID, ChipID_];
	
		//baseUrlString = @"http://cydia.saurik.com/TSS/controller?action=2";
	
	
	url = [NSURL URLWithString:baseUrlString];
	
    success = (url != nil);
	
	//NSLog(@"URL: %@", url);
		
	
		// If the URL is bogus, let the user know.  Otherwise kick off the connection.
    
    if ( ! success) {
		assert(!success);
		
			//self.statusLabel.text = @"Invalid URL";
    } else {
		
		
			// Open a connection for the URL.
		
        request = [self requestForBlob:theBlob];
			//[request setHTTPMethod:@"POST"];
		
        assert(request != nil);
        
        self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
        assert(self.connection != nil);
		
			// Tell the UI we're receiving.
        
        [self _receiveDidStart];
    }
}
	
- (NSString *)_synchronousPushBlob:(NSString *)theBlob
{
	if ([TSSCommon internetAvailable] == FALSE)
	{
		
		NSLog(@"no internet available, should we bail?!");
			//	return nil;
		
	}
	//NSLog(@"pushingBlob: %@", theBlob);
    BOOL                success;
    NSURL *             url;
    NSMutableURLRequest *      request;
    
	TSSDeviceID cd = self.theDevice;
	
	//[self logDevice:cd];
	// First get and check the URL.
    

	baseUrlString = [NSString stringWithFormat:@"http://cydia.saurik.com/tss@home/api/store/%i/%i/%@", cd.chipID, cd.boardID, ChipID_];
	
	//baseUrlString = @"http://cydia.saurik.com/TSS/controller?action=2";
	
	
	url = [NSURL URLWithString:baseUrlString];
	
    success = (url != nil);
	
	//NSLog(@"URL: %@", url);
	
	
	// If the URL is bogus, let the user know.  Otherwise kick off the connection.
    
    if ( ! success) {
		assert(!success);
		
		//self.statusLabel.text = @"Invalid URL";
    } else {
		
		
		// Open a connection for the URL.
		
        request = [self requestForBlob:theBlob];
		assert(request != nil);
   

		NSHTTPURLResponse * theResponse = nil;
		[NSURLConnection sendSynchronousRequest:request returningResponse:&theResponse error:nil];
		
	
		NSString *returnString = [NSString stringWithFormat:@"Request returned with response: \"%@\" with status code: %i",[NSHTTPURLResponse localizedStringForStatusCode:theResponse.statusCode], theResponse.statusCode ];
	
		
		return returnString;
		
		
	}
	
	return nil;
}


- (NSString *)_synchronousCydiaReceiveVersion:(NSString *)theVersion
{
	if ([TSSCommon internetAvailable] == FALSE)
	{
		
		NSLog(@"no internet available, bail!");
		return nil;
		
	}
		//NSLog(@"receivingVersion: %@", theVersion);
    BOOL                success;
    NSURL *             url;
    NSMutableURLRequest *      request;
		//receivedData =		[[NSMutableData data] retain];
		//assert(self.connection == nil);         // don't tap receive twice in a row!
	
	
		// First get and check the URL.
    
		//baseUrlString = @"http://gs.apple.com/TSS/controller?action=2";
	
		baseUrlString = @"http://cydia.saurik.com/TSS/controller?action=2";
	
	
	url = [NSURL URLWithString:baseUrlString];
	
    success = (url != nil);
	
		//NSLog(@"URL: %@", url);
		//LocationLog(@"URL: %@", url);
	
	
		// If the URL is bogus, let the user know.  Otherwise kick off the connection.
    
    if ( ! success) {
		assert(!success);
		
			//self.statusLabel.text = @"Invalid URL";
    } else {
		
		
			// Open a connection for the URL.
		
        request = [self postRequestFromVersion:theVersion];
			//[request setHTTPMethod:@"POST"];
		
		
		NSURLResponse *theResponse = nil;
		NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:&theResponse error:nil];
		
		NSString *datString = [[NSString alloc] initWithData:returnData  encoding:NSUTF8StringEncoding];
		
		NSString *outString = [TSSManager rawBlobFromResponse:datString]; 
		
		[datString release];
		
		return outString;
		
    }
	
	return nil;
}

- (NSString *)_synchronousReceiveVersion:(NSString *)theVersion
{
	//NSLog(@"receivingVersion: %@", theVersion);
    BOOL                success;
    NSURL *             url;
    NSMutableURLRequest *      request;
    //receivedData =		[[NSMutableData data] retain];
    //assert(self.connection == nil);         // don't tap receive twice in a row!
	
	
	// First get and check the URL.
    
	baseUrlString = @"http://gs.apple.com/TSS/controller?action=2";
	
	//baseUrlString = @"http://cydia.saurik.com/TSS/controller?action=2";
	
	
	url = [NSURL URLWithString:baseUrlString];
	
    success = (url != nil);
	
	//NSLog(@"URL: %@", url);
	//LocationLog(@"URL: %@", url);
	
	
	// If the URL is bogus, let the user know.  Otherwise kick off the connection.
    
    if ( ! success) {
		assert(!success);
		
		//self.statusLabel.text = @"Invalid URL";
    } else {
		
		
		// Open a connection for the URL.
		
        request = [self postRequestFromVersion:theVersion];
		//[request setHTTPMethod:@"POST"];
		
		
		NSURLResponse *theResponse = nil;
		NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:&theResponse error:nil];
		
		NSString *datString = [[NSString alloc] initWithData:returnData  encoding:NSUTF8StringEncoding];
		
		NSString *outString = [TSSManager rawBlobFromResponse:datString]; 
		
		[datString release];
		
		return outString;
      
    }
}

	//http://cydia.saurik.com/tss@home/api/check/%llu <--ecid
		
- (void)_receiveVersion:(NSString *)theVersion
{
    BOOL                success;
    NSURL *             url;
    NSMutableURLRequest *      request;
    receivedData =		[[NSMutableData data] retain];
    assert(self.connection == nil);         // don't tap receive twice in a row!
	
	
		// First get and check the URL.
    
	baseUrlString = @"http://gs.apple.com/TSS/controller?action=2";
	
		//baseUrlString = @"http://cydia.saurik.com/TSS/controller?action=2";
	
	
	url = [NSURL URLWithString:baseUrlString];
	
    success = (url != nil);
	
		//NSLog(@"URL: %@", url);
		//LocationLog(@"URL: %@", url);
	
	
		// If the URL is bogus, let the user know.  Otherwise kick off the connection.
    
    if ( ! success) {
		assert(!success);
		
			//self.statusLabel.text = @"Invalid URL";
    } else {
		
		
			// Open a connection for the URL.
		
        request = [self postRequestFromVersion:theVersion];
			//[request setHTTPMethod:@"POST"];
		
        assert(request != nil);
        
        self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
        assert(self.connection != nil);
		
			// Tell the UI we're receiving.
        
        [self _receiveDidStart];
    }
}

- (void)_startReceive
	// Starts a connection to download the current URL.
{
    BOOL                success;
    NSURL *             url;
    NSMutableURLRequest *      request;
    receivedData =		[[NSMutableData data] retain];
    assert(self.connection == nil);         // don't tap receive twice in a row!
	
	
		// First get and check the URL.
    
	baseUrlString = @"http://gs.apple.com/TSS/controller?action=2";
	
		//baseUrlString = @"http://cydia.saurik.com/TSS/controller?action=2";
	
	
	url = [NSURL URLWithString:baseUrlString];

    success = (url != nil);
	
		//NSLog(@"URL: %@", url);
		//LocationLog(@"URL: %@", url);
	
	
		// If the URL is bogus, let the user know.  Otherwise kick off the connection.
    
    if ( ! success) {
		assert(!success);
		
			//self.statusLabel.text = @"Invalid URL";
    } else {
		
		
			// Open a connection for the URL.
		
        request = [self postRequestFromVersion:[TSSCommon osBuild]];
			//[request setHTTPMethod:@"POST"];
		
        assert(request != nil);
        
        self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
        assert(self.connection != nil);
		
			// Tell the UI we're receiving.
        
        [self _receiveDidStart];
    }
}

- (void)_stopReceiveWithStatus:(int)status
	// Shuts down the connection and displays the result (statusString == nil) 
	// or the error status (otherwise).
{
    if (self.connection != nil) {
        [self.connection cancel];
        self.connection = nil;
		
    }
	if (receivedData != nil) {
        receivedData = nil;
		
    }
		
}

- (void)connection:(NSURLConnection *)theConnection didReceiveResponse:(NSURLResponse *)response
	// A delegate method called by the NSURLConnection when the request/response 
	// exchange is complete.  We look at the response to check that the HTTP 
	// status code is 2xx and that the Content-Type is acceptable.  If these checks 
	// fail, we give up on the transfer.
{
		
		NSString *          contentTypeHeader;
		
		NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *) response;
		assert( [httpResponse isKindOfClass:[NSHTTPURLResponse class]] );
		//NSLog(@"didReceiveResponse: %@ statusCode: %i", [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode], httpResponse.statusCode);
		if ((httpResponse.statusCode / 100) != 2) {
				//[self _stopReceiveWithStatus:[httpResponse statusCode]];
		} else {
			
		}
		
	
	[receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)theConnection didReceiveData:(NSData *)data
	// A delegate method called by the NSURLConnection as data arrives.  We just 
	// write the data to the file.
{

	[receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)theConnection didFailWithError:(NSError *)error
	// A delegate method called by the NSURLConnection if the connection fails. 
	// We shut down the connection and display the failure.  Production quality code 
	// would either display or log the actual error.
{
#pragma unused(theConnection)
#pragma unused(error)
    assert(theConnection == self.connection);
    
    [self _stopReceiveWithStatus:-1];
	[receivedData release];
}



- (void)connectionDidFinishLoading:(NSURLConnection *)theConnection
	// A delegate method called by the NSURLConnection when the connection has been 
	// done successfully.  We shut down the connection with a nil status, which 
	// causes the image to be displayed.
{
	
#pragma unused(theConnection)
    assert(theConnection == self.connection);
    
	NSString *datString = [[NSString alloc] initWithData:receivedData  encoding:NSUTF8StringEncoding];
	
	self._returnDataAsString = [datString copy];
	
	[datString release];

	
    [self _stopReceiveWithStatus:0];
	[self _receiveDidStopWithStatus:0];
}

#pragma mark * UI Actions

- (void)getOrCancelAction:(id)sender
{
#pragma unused(sender)
    if (self.isReceiving) {
        [self _stopReceiveWithStatus:0];
    } else {
        [self _startReceive];
    }
}




- (void)dealloc {
    [self _stopReceiveWithStatus:0];
	
	
    [super dealloc];
}



@end
