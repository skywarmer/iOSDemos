//
//  HWURLProtocol.m
//  NSURLProtocolDemo
//
//  Created by Hongsheng Wang on 9/20/16.
//  Copyright © 2016 Hongsheng Wang. All rights reserved.
//

#import "HWURLProtocol.h"
#import "CachedURLResponse.h"
#import "AppDelegate.h"


/**
 
 Reference: 
 1. https://www.raywenderlich.com/59982/nsurlprotocol-tutorial
 2. http://nshipster.com/nsurlprotocol/
 
 
 ### supported schemes:
 1. http://
 2. https://
 3. ftp://
 4. file://
 5. data://
 
 
> Registering the Subclass with the URL Loading System
> In order to actually use an NSURLProtocol subclass, it needs to be registered into the URL Loading System
> When a request is loaded, each registered protocol is asked “hey, can you handle this request?”. The first one to respond with YES with +canInitWithRequest: gets to handle the request. URL protocols are consulted in reverse order of when they were registered, so by calling [NSURLProtocol registerClass:[MyURLProtocol class]]; in -application:didFinishLoadingWithOptions:, your protocol will have priority over any of the built-in protocols. 
> http://nshipster.com/nsurlprotocol/
 
 
 Do remember to **register** customized NSURLProtocol class using `+registerClass:` of `NSURLProtocol` before trigger a request!
 
 */

static NSString * const kHWURLProtocolPropertyKey = @"kHWURLProtocolPropertyKey";

@interface HWURLProtocol () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, strong) NSURLResponse *response;
@end

@implementation HWURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    
    if ([NSURLProtocol propertyForKey:kHWURLProtocolPropertyKey inRequest:request]) {
        return NO;
    }
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    
    NSMutableURLRequest *newRequest = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHWURLProtocolPropertyKey inRequest:newRequest];
    return [newRequest copy];
}


- (void)startLoading {
    // 先查找 local cache
    CachedURLResponse *cachedResponse = [self cachedResponseForCurrentRequest];
    if (cachedResponse) {
        // 根据缓存数据创建 NSURLResponse
        NSURLResponse *response = [[NSURLResponse alloc] initWithURL:self.request.URL
                                                            MIMEType:cachedResponse.mimeType
                                               expectedContentLength:cachedResponse.data.length
                                                    textEncodingName:cachedResponse.encoding];
        // communicate with NSURLProtocol client
        [self.client URLProtocol:self
              didReceiveResponse:response
              cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        
        [self.client URLProtocol:self
                     didLoadData:cachedResponse.data];
        
        [self.client URLProtocolDidFinishLoading:self];
    } else {
       // fetch data from internet
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        self.connection = [NSURLConnection connectionWithRequest:[[self class] canonicalRequestForRequest:self.request]
                                                        delegate:self];
#pragma clang diagnostic pop
    }
}

- (void)stopLoading {
    [self.connection cancel];
    self.connection = nil;
}


- (CachedURLResponse *)cachedResponseForCurrentRequest {
    
    AppDelegate *delegate = [UIApplication sharedApplication].delegate;
    NSManagedObjectContext *context = delegate.managedObjectContext;
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"CachedURLResponse"
                                                      inManagedObjectContext:context];
    fetchRequest.entity = entity;
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"url == %@", self.request.URL.absoluteString];
    fetchRequest.predicate = predicate;
    
    
    NSError *error;
    NSArray *result = [context executeFetchRequest:fetchRequest
                                             error:&error];
    
    if (result && result.count > 0) {
        return [result firstObject];
    }
    
    return nil;
}

- (void)saveCachedResponse {
    AppDelegate *appDelegate = [UIApplication sharedApplication].delegate;
    NSManagedObjectContext *context = appDelegate.managedObjectContext;
    
    CachedURLResponse *cachedResponse = [NSEntityDescription insertNewObjectForEntityForName:@"CachedURLResponse"
                                                                      inManagedObjectContext:context];
    cachedResponse.url = self.request.URL.absoluteString;
    cachedResponse.data = [self.mutableData copy];
    cachedResponse.mimeType = self.response.MIMEType;
    cachedResponse.encoding = self.response.textEncodingName;
    cachedResponse.timestamp = [NSDate date];
    
    NSError *error;
    if ([context save:&error]) {
        NSLog(@"Could not cache the response");
    }
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    self.response = response;
    self.mutableData = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
    [self.mutableData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.client URLProtocolDidFinishLoading:self];
    [self saveCachedResponse];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.client URLProtocol:self didFailWithError:error];
}
@end
