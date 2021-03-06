/*
 Copyright (c) 2010, The Barbarian Group
 All rights reserved.

 Redistribution and use in source and binary forms, with or without modification, are permitted provided that
 the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions and
	the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and
	the following disclaimer in the documentation and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
 WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
*/

#import "cinder/cocoa/CinderCocoa.h"
#include "cinder/Url.h"
#include "cinder/Buffer.h"
#include "cinder/Font.h"

#if defined( CINDER_MAC )
	#import <Cocoa/Cocoa.h>
	#import <CoreVideo/CVPixelBuffer.h>
	#import <AppKit/AppKit.h>
#else
	#import <UIKit/UIKit.h>
#endif
#import <Foundation/NSData.h>


namespace cinder { namespace cocoa {

SafeNsString::SafeNsString( const NSString *str )
{
	[str retain];
	mPtr = shared_ptr<NSString>( str, safeRelease );
}

SafeNsString::SafeNsString( const std::string &str )
{
	mPtr = shared_ptr<NSString>( [NSString stringWithUTF8String:str.c_str()], safeRelease );
	[mPtr.get() retain];
}

void SafeNsString::safeRelease( const NSString *ptr )
{
	if( ptr )
		[ptr release];
}

SafeNsString::operator std::string() const
{
	if( ! mPtr )
		return std::string();
	else
		return std::string( [mPtr.get() UTF8String] );
}

SafeNsData::SafeNsData( const Buffer &buffer )
	: mBuffer( buffer )
{
	mPtr = shared_ptr<NSData>( [NSData dataWithBytesNoCopy:const_cast<void*>( buffer.getData() ) length:buffer.getDataSize() freeWhenDone:NO], safeRelease );
	if( mPtr.get() )
		[mPtr.get() retain];
}

void SafeNsData::safeRelease( const NSData *ptr )
{
	if( ptr )
		[ptr release];
}

SafeNsAutoreleasePool::SafeNsAutoreleasePool()
{
	[NSThread currentThread]; // register this thread with garbage collection
	mPool = [[NSAutoreleasePool alloc] init];
}

SafeNsAutoreleasePool::~SafeNsAutoreleasePool()
{
	[((NSAutoreleasePool*)mPool) drain];
}

void safeCfRelease( const CFTypeRef cfRef )
{
	if( cfRef != NULL )
		::CFRelease( cfRef );
}

void safeCocoaRelease( void *nsObject )
{
	if( nsObject )
		[(NSObject*)nsObject release];
}

CGContextRef createCgBitmapContext( const Surface8u &surface )
{
	// See the enumeration of Supported Pixel Formats in the Quartz 2D Programming Guide
	// http://developer.apple.com/mac/library/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html#//apple_ref/doc/uid/TP30001066-CH203-BCIBHHBB
	// Sadly, unpremultipllied alpha is not amongst them
	CGColorSpaceRef colorSpace = ::CGColorSpaceCreateDeviceRGB();
	CGImageAlphaInfo alphaInfo;
	switch( surface.getChannelOrder().getCode() ) {
		case SurfaceChannelOrder::RGBA:
			alphaInfo = kCGImageAlphaPremultipliedLast;
		break;
		case SurfaceChannelOrder::ARGB:
			alphaInfo = kCGImageAlphaPremultipliedFirst;
		break;
		case SurfaceChannelOrder::RGBX:
			alphaInfo = kCGImageAlphaNoneSkipLast;
		break;
		case SurfaceChannelOrder::XRGB:
			alphaInfo = kCGImageAlphaNoneSkipFirst;
		break;
		// CGBitmapContextCreate cannont handle this option despite the existence of this constant
		/*case SurfaceChannelOrder::RGB:
			alphaInfo = kCGImageAlphaNone;
		break;*/
		default:
			throw;
	}
	CGContextRef context = CGBitmapContextCreate( const_cast<uint8_t*>( surface.getData() ), surface.getWidth(), surface.getHeight(), 8, surface.getRowBytes(), colorSpace, alphaInfo );
	CGColorSpaceRelease( colorSpace );
	return context;
}

// This will get called when the Surface::Obj is destroyed
static void NSBitmapImageRepSurfaceDeallocator( void *refcon )
{
	NSBitmapImageRep *rep = reinterpret_cast<NSBitmapImageRep*>( refcon );
	[rep release];
}

#if defined( CINDER_MAC )
Surface8u convertNsBitmapDataRep( const NSBitmapImageRep *rep, bool assumeOwnership )
{
	int bpp = [rep bitsPerPixel];
	int rowBytes = [rep bytesPerRow];
	int width = [rep pixelsWide];
	int height = [rep pixelsHigh];
	uint8_t *data = [rep bitmapData];
	SurfaceChannelOrder co = ( bpp == 24 ) ? SurfaceChannelOrder::RGB : SurfaceChannelOrder::RGBA;
	Surface8u result( data, width, height, rowBytes, co );
	// If requested, point the result's deallocator to the appropriate function. This will get called when the Surface::Obj is destroyed
	if( assumeOwnership )
		result.setDeallocator( NSBitmapImageRepSurfaceDeallocator, const_cast<NSBitmapImageRep*>( rep ) );
	return result;
}
#endif defined( CINDER_MAC )

std::string convertCfString( CFStringRef str )
{
	char buffer[4096];
	Boolean worked = CFStringGetCString( str, buffer, 4095, kCFStringEncodingUTF8 );
	if( worked ) {
		std::string result( buffer );
		return result;
	}
	else
		return std::string();
}

CFStringRef	createCfString( const std::string &str )
{
	CFStringRef result = CFStringCreateWithCString( kCFAllocatorDefault, str.c_str(), kCFStringEncodingUTF8 );
	return result;
}

SafeCfString createSafeCfString( const std::string &str )
{
	CFStringRef result = CFStringCreateWithCString( kCFAllocatorDefault, str.c_str(), kCFStringEncodingUTF8 );
	if( result )
		return SafeCfString( result, safeCfRelease );
	else
		return SafeCfString();
}

std::string	convertNsString( NSString *str )
{
	return std::string( [str UTF8String] );
}

CFURLRef createCfUrl( const Url &url )
{
	::CFStringRef pathString = createCfString( url.str() );
	::CFURLRef result = ::CFURLCreateWithString( kCFAllocatorDefault, pathString, NULL );
	::CFRelease( pathString );
	return result;
}

#if defined( CINDER_MAC )
CFAttributedStringRef createCfAttributedString( const std::string &str, const Font &font, const ColorA &color )
{
	CGColorRef cgColor = createCgColor( color );
	const CFStringRef keys[] = {
		kCTFontAttributeName,
		kCTForegroundColorAttributeName
	};
	const CFTypeRef values[] = {
		font.getCtFontRef(),
		cgColor
	};
	
	// Create our attributes
	CFDictionaryRef attributes = ::CFDictionaryCreate(kCFAllocatorDefault, (const void**)&keys, (const void**)&values, sizeof(keys)/sizeof(keys[0]), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	assert( attributes != NULL );

	CGColorRelease( cgColor );
	
	// Create the attributed string
	CFStringRef strRef = CFStringCreateWithCString( kCFAllocatorDefault, str.c_str(), kCFStringEncodingUTF8 );
	CFAttributedStringRef attrString = ::CFAttributedStringCreate( kCFAllocatorDefault, strRef, attributes );
	
	CFRelease( strRef );
	CFRelease( attributes );
	
	return attrString;
}
#endif //defined( CINDER_MAC )

CGColorRef createCgColor( const Color &color )
{
	shared_ptr<CGColorSpace> safeColor( ::CGColorSpaceCreateDeviceRGB(), ::CGColorSpaceRelease );
	CGFloat components[4] = { color.r, color.g, color.b, 1 };
	return ::CGColorCreate( safeColor.get(), components );
}

CGColorRef createCgColor( const ColorA &color )
{
	shared_ptr<CGColorSpace> safeColor( ::CGColorSpaceCreateDeviceRGB(), ::CGColorSpaceRelease );
	CGFloat components[4] = { color.r, color.g, color.b, color.a };
	return ::CGColorCreate( safeColor.get(), components );
}

CGRect createCgRect( const Area &area )
{
	CGRect result;
	result.size.width = area.getWidth();
	result.size.height = area.getHeight();
	result.origin.x = area.getX1();
	result.origin.y = area.getY1();
	return result;
}

Area CgRectToArea( const CGRect &rect )
{
	return Area( rect.origin.x, rect.origin.y, rect.origin.x + rect.size.width, rect.origin.y + rect.size.height );
}

namespace { // anonymous namespace
extern "C" void cgPathApplierFunc( void *info, const CGPathElement *el )
{
	Shape2d *path = reinterpret_cast<Shape2d*>( info );

    switch( el->type ) {
		case kCGPathElementMoveToPoint:
			path->moveTo( el->points[0].x, el->points[0].y );
		break;
		case kCGPathElementAddLineToPoint:
			path->lineTo( el->points[0].x, el->points[0].y );
		break;
		case kCGPathElementAddQuadCurveToPoint:
			path->quadTo( el->points[0].x, el->points[0].y, el->points[1].x, el->points[1].y );
		break;
		case kCGPathElementAddCurveToPoint:
			path->curveTo( el->points[0].x, el->points[0].y, el->points[1].x, el->points[1].y, el->points[2].x, el->points[2].y );
		break;
		case kCGPathElementCloseSubpath:
			path->close();
		break;
	}
}

extern "C" void cgPathApplierFlippedFunc( void *info, const CGPathElement *el )
{
	Shape2d *path = reinterpret_cast<Shape2d*>( info );

    switch( el->type ) {
		case kCGPathElementMoveToPoint:
			path->moveTo( el->points[0].x, -el->points[0].y );
		break;
		case kCGPathElementAddLineToPoint:
			path->lineTo( el->points[0].x, -el->points[0].y );
		break;
		case kCGPathElementAddQuadCurveToPoint:
			path->quadTo( el->points[0].x, -el->points[0].y, el->points[1].x, -el->points[1].y );
		break;
		case kCGPathElementAddCurveToPoint:
			path->curveTo( el->points[0].x, -el->points[0].y, el->points[1].x, -el->points[1].y, el->points[2].x, -el->points[2].y );
		break;
		case kCGPathElementCloseSubpath:
			path->close();
		break;
	}
}
} // anonymous namespace

void convertCgPath( CGPathRef cgPath, cinder::Shape2d *resultShape, bool flipVertical )
{
	resultShape->clear();
	if( flipVertical )
		CGPathApply( cgPath, resultShape, cgPathApplierFlippedFunc );
	else
		CGPathApply( cgPath, resultShape, cgPathApplierFunc );
}

#if defined( CINDER_MAC )
int getCvPixelFormatTypeFromSurfaceChannelOrder( const SurfaceChannelOrder &sco )
{
	switch( sco.getCode() ) {
		case SurfaceChannelOrder::RGB:
			return kCVPixelFormatType_24RGB;
		break;
		case SurfaceChannelOrder::BGR:
			return kCVPixelFormatType_24BGR;
		break;
		case SurfaceChannelOrder::ARGB:
			return kCVPixelFormatType_32ARGB;
		break;
		case SurfaceChannelOrder::BGRA:
			return kCVPixelFormatType_32BGRA;
		break;
		case SurfaceChannelOrder::ABGR:
			return kCVPixelFormatType_32ABGR;
		break;
		case SurfaceChannelOrder::RGBA:
			return kCVPixelFormatType_32RGBA;
		break;
		default:
			return -1;
	}
}
#endif // defined( CINDER_MAC )

CFDataRef createCfDataRef( const Buffer &buffer )
{
	return ::CFDataCreateWithBytesNoCopy( kCFAllocatorDefault, reinterpret_cast<const UInt8*>( buffer.getData() ), buffer.getDataSize(), kCFAllocatorNull );
}

///////////////////////////////////////////////////////////////////////////////////////////////
// ImageSourceCgImage
ImageSourceCgImageRef ImageSourceCgImage::createRef( ::CGImageRef imageRef )
{
	return shared_ptr<ImageSourceCgImage>( new ImageSourceCgImage( imageRef ) );
}

ImageSourceCgImage::ImageSourceCgImage( ::CGImageRef imageRef )
	: ImageSource(), mImageRef( imageRef )
{
	::CGImageRetain( mImageRef );
	
	setSize( ::CGImageGetWidth( mImageRef ), ::CGImageGetHeight( mImageRef ) );
	size_t bpc = ::CGImageGetBitsPerComponent( mImageRef );
	//size_t bpp = ::CGImageGetBitsPerPixel( mImageRef );

	// translate data types
	::CGBitmapInfo bitmapInfo = ::CGImageGetBitmapInfo( mImageRef );
	bool isFloat = ( bitmapInfo & kCGBitmapFloatComponents ) != 0;
	::CGImageAlphaInfo alphaInfo = ::CGImageGetAlphaInfo( mImageRef );
	if( isFloat )
		setDataType( ImageIo::FLOAT32 );
	else
		setDataType( ( bpc == 16 ) ? ImageIo::UINT16 : ImageIo::UINT8 );
	if( isFloat && ( bpc != 32 ) )
		throw ImageIoExceptionIllegalDataType(); // we don't know how to handle half-sized floats yet, but Quartz seems to make them 32bit anyway
	bool hasAlpha = ( alphaInfo != kCGImageAlphaNone ) && ( alphaInfo != kCGImageAlphaNoneSkipLast ) && ( alphaInfo != kCGImageAlphaNoneSkipFirst );

	bool swapEndian = false;
	if( bitmapInfo & kCGBitmapByteOrder32Little )
		swapEndian = true;
	
	// translate color space
	::CGColorSpaceRef colorSpace = ::CGImageGetColorSpace( mImageRef );
	switch( ::CGColorSpaceGetModel( colorSpace ) ) {
		case kCGColorSpaceModelMonochrome:
			setColorModel( ImageIo::CM_GRAY );
			setChannelOrder( ( hasAlpha ) ? ImageIo::YA : ImageIo::Y );
		break;
		case kCGColorSpaceModelRGB:
			setColorModel( ImageSource::CM_RGB );
			switch( alphaInfo ) {
				case kCGImageAlphaNone:
					setChannelOrder( (swapEndian) ? ImageIo::BGR : ImageIo::RGB );
				break;
				case kCGImageAlphaPremultipliedLast:
					setChannelOrder( (swapEndian) ? ImageIo::ABGR : ImageIo::RGBA ); setPremultiplied( true );
				break;
				case kCGImageAlphaLast:
					setChannelOrder( (swapEndian) ? ImageIo::ABGR : ImageIo::RGBA );
				break;
				case kCGImageAlphaPremultipliedFirst:
					setChannelOrder( (swapEndian) ? ImageIo::BGRA : ImageIo::ARGB ); setPremultiplied( true );
				break;
				case kCGImageAlphaFirst:
					setChannelOrder( (swapEndian) ? ImageIo::BGRA : ImageIo::ARGB );
				break;
				case kCGImageAlphaNoneSkipFirst:
					setChannelOrder( (swapEndian) ? ImageIo::BGRX : ImageIo::XRGB );
				break;
				case kCGImageAlphaNoneSkipLast:
					setChannelOrder( (swapEndian) ? ImageIo::XBGR : ImageIo::RGBX );
				break;
			}
		break;
		default: // we only support Gray and RGB data for now
			throw ImageIoExceptionIllegalColorModel();
		break;
	}
}

ImageSourceCgImage::~ImageSourceCgImage()
{
	::CGImageRelease( mImageRef );
}

void ImageSourceCgImage::load( ImageTargetRef target )
{
	int32_t rowBytes = ::CGImageGetBytesPerRow( mImageRef );	
	::CFDataRef pixels = ::CGDataProviderCopyData( ::CGImageGetDataProvider( mImageRef ) );
	
	// get a pointer to the ImageSource function appropriate for handling our data configuration
	ImageSource::RowFunc func = setupRowFunc( target );
	
	const uint8_t *data = ::CFDataGetBytePtr( pixels );
	for( int32_t row = 0; row < mHeight; ++row ) {
		((*this).*func)( target, row, data );
		data += rowBytes;
	}
	
	::CFRelease( pixels );
}

ImageSourceCgImageRef createImageSource( ::CGImageRef imageRef )
{
	return ImageSourceCgImage::createRef( imageRef );
}


///////////////////////////////////////////////////////////////////////////////////////////////
// ImageTargetCgImage
ImageTargetCgImageRef ImageTargetCgImage::createRef( ImageSourceRef imageSource )
{
	return ImageTargetCgImageRef( new ImageTargetCgImage( imageSource ) );
}

ImageTargetCgImage::ImageTargetCgImage( ImageSourceRef imageSource )
	: ImageTarget(), mImageRef( 0 )
{
	setSize( (size_t)imageSource->getWidth(), (size_t)imageSource->getHeight() );
	mBitsPerComponent = 32;
	bool writingAlpha = imageSource->hasAlpha();
	bool isFloat = true;
	switch( imageSource->getDataType() ) {
		case ImageIo::UINT8: mBitsPerComponent = 8; isFloat = false; setDataType( ImageIo::UINT8 ); break;
		case ImageIo::UINT16: mBitsPerComponent = 16; isFloat = false; setDataType( ImageIo::UINT16 ); break;
		default: mBitsPerComponent = 32; isFloat = true; setDataType( ImageIo::FLOAT32 );
	}
	uint8_t numChannels;
	switch( imageSource->getColorModel() ) {
		case ImageIo::CM_GRAY:
			numChannels = ( writingAlpha ) ? 2 : 1; break;
		default:
			numChannels = ( writingAlpha ) ? 4 : 3;
	}
	mBitsPerPixel = numChannels * mBitsPerComponent;
	mRowBytes = mWidth * ( numChannels * mBitsPerComponent ) / 8;
	setColorModel( ( imageSource->getColorModel() == ImageIo::CM_GRAY ) ? ImageIo::CM_GRAY : ImageIo::CM_RGB );
	
	mBitmapInfo = ( isFloat ) ? ( kCGBitmapByteOrder32Little | kCGBitmapFloatComponents ) : kCGBitmapByteOrderDefault;
	if( writingAlpha ) {
		mBitmapInfo |= ( imageSource->isPremultiplied() ) ? kCGImageAlphaPremultipliedLast : kCGImageAlphaLast;
		if( mColorModel == CM_GRAY )
			setChannelOrder( ImageIo::YA );
		else
			setChannelOrder( ImageIo::RGBA );
	}
	else {
		if( mColorModel == CM_GRAY )
			setChannelOrder( ImageIo::Y );
		else {
			setChannelOrder( ImageIo::RGB );		
			mBitmapInfo |= kCGImageAlphaNone;
		}
	}
	
	mDataRef = ::CFDataCreateMutable( kCFAllocatorDefault, mHeight * mRowBytes );
	::CFDataIncreaseLength( mDataRef, mHeight * mRowBytes );
	mDataPtr = ::CFDataGetMutableBytePtr( mDataRef );
}

ImageTargetCgImage::~ImageTargetCgImage()
{
	::CFRelease( mDataRef );
	if( mImageRef )
		::CGImageRelease( mImageRef );
}

void* ImageTargetCgImage::getRowPointer( int32_t row )
{
	return &mDataPtr[row * mRowBytes];
}

void ImageTargetCgImage::finalize()
{
	shared_ptr<CGColorSpace> colorSpaceRef( ( mColorModel == ImageIo::CM_GRAY ) ? ::CGColorSpaceCreateDeviceGray() : ::CGColorSpaceCreateDeviceRGB(), ::CGColorSpaceRelease );
	shared_ptr<CGDataProvider> dataProvider( ::CGDataProviderCreateWithCFData( mDataRef ), ::CGDataProviderRelease );

	mImageRef = ::CGImageCreate( mWidth, mHeight, mBitsPerComponent, mBitsPerPixel, mRowBytes,
			colorSpaceRef.get(), mBitmapInfo, dataProvider.get(), NULL, false, kCGRenderingIntentDefault );
}

::CGImageRef createCgImage( ImageSourceRef imageSource )
{
	ImageTargetCgImageRef target = ImageTargetCgImage::createRef( imageSource );
	imageSource->load( target );
	target->finalize();
	::CGImageRef result( target->getCgImage() );
	::CGImageRetain( result );
	return result;
}


} } // namespace cinder::cocoa


namespace cinder {

SurfaceChannelOrder SurfaceConstraintsCgBitmapContext::getChannelOrder( bool alpha ) const
{
	return ( alpha ) ? SurfaceChannelOrder::RGBA : SurfaceChannelOrder::RGBX;
}

int32_t SurfaceConstraintsCgBitmapContext::getRowBytes( int requestedWidth, const SurfaceChannelOrder &sco, int elementSize ) const
{
	return requestedWidth * elementSize * 4;
}

} // namespace cinder
