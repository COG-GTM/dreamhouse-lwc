import { createElement } from '@lwc/engine-dom';
import PropertyCarousel from 'c/propertyCarousel';
import { getRecord } from 'lightning/uiRecordApi';
import { processImage } from 'lightning/mediaUtils';
import { refreshApex } from '@salesforce/apex';
import getPictures from '@salesforce/apex/PropertyController.getPictures';
import createFile from '@salesforce/apex/FileUtilities.createFile';

// Realistic data with multiple records
const mockGetPictures = require('./data/getPictures.json');

// Mock realistic data
const mockGetPropertyRecord = require('./data/getPropertyRecord.json');

// Mock getPictures Apex wire adapter
jest.mock(
    '@salesforce/apex/PropertyController.getPictures',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);

// Mocking createFile imperative Apex method call
jest.mock(
    '@salesforce/apex/FileUtilities.createFile',
    () => {
        return {
            default: jest.fn()
        };
    },
    { virtual: true }
);

describe('c-property-carousel', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // Helper function to wait until the microtask queue is empty.
    // Used when having to wait for asynchronous DOM updates.
    async function flushPromises() {
        return Promise.resolve();
    }

    describe('@wire data', () => {
        it('renders carousel with pictures when property and pictures returned', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            document.body.appendChild(element);

            // Emit mock property
            getRecord.emit(mockGetPropertyRecord);

            // Emit mock pictures
            getPictures.emit(mockGetPictures);

            // Wait for any asynchronous DOM updates
            await flushPromises();

            const carouselEl =
                element.shadowRoot.querySelector('lightning-carousel');
            expect(carouselEl).not.toBeNull();
            const carouselImageEls = element.shadowRoot.querySelectorAll(
                'lightning-carousel-image'
            );
            expect(carouselImageEls.length).toBe(mockGetPictures.length);
            carouselImageEls.forEach((imageEl, index) => {
                expect(imageEl.src).toBe(
                    `/sfc/servlet.shepherd/version/download/${mockGetPictures[index].Id}`
                );
                expect(imageEl.description).toBe(mockGetPictures[index].Title);
            });
        });

        it('shows the property address as the card title', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            document.body.appendChild(element);

            getRecord.emit(mockGetPropertyRecord);
            getPictures.emit(mockGetPictures);

            await flushPromises();

            const titleEl =
                element.shadowRoot.querySelector('span[slot="title"]');
            expect(titleEl.textContent).toBe(
                mockGetPropertyRecord.fields.Address__c.value
            );
        });

        it('renders no pictures message when pictures become empty', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            document.body.appendChild(element);

            getRecord.emit(mockGetPropertyRecord);
            getPictures.emit(mockGetPictures);
            await flushPromises();

            // All pictures removed
            getPictures.emit([]);
            await flushPromises();

            expect(
                element.shadowRoot.querySelector('lightning-carousel')
            ).toBeNull();
            const pEl = element.shadowRoot.querySelector(
                'p.slds-text-align_center'
            );
            expect(pEl).not.toBeNull();
        });

        it('passes both errors to the error panel when both wires fail', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            document.body.appendChild(element);

            getRecord.error();
            getPictures.error();

            await flushPromises();

            const errorPanelEl =
                element.shadowRoot.querySelector('c-error-panel');
            expect(errorPanelEl.friendlyMessage).toBe(
                'Error retrieving pictures'
            );
            expect(errorPanelEl.errors.length).toBe(2);
        });

        it('renders no pictures message when property but no pictures returned', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            document.body.appendChild(element);

            // Emit mock property
            getRecord.emit(mockGetPropertyRecord);

            // Emit no pictures
            getPictures.emit(null);

            // Wait for any asynchronous DOM updates
            await flushPromises();

            const pEl = element.shadowRoot.querySelector(
                'p.slds-text-align_center'
            );
            expect(pEl).not.toBeNull();
            expect(pEl.textContent).toBe(
                'There are currently no pictures for this property.'
            );
        });

        it('renders error when getProperty returns error', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            document.body.appendChild(element);

            // Emit error
            getRecord.error();

            // Wait for any asynchronous DOM updates
            await flushPromises();

            const errorPanelEl =
                element.shadowRoot.querySelector('c-error-panel');
            expect(errorPanelEl).not.toBeNull();
        });

        it('renders error when getPictures returns error', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            document.body.appendChild(element);

            // Emit mock property
            getRecord.emit(mockGetPropertyRecord);

            // Emit error
            getPictures.error();

            // Wait for any asynchronous DOM updates
            await flushPromises();

            const errorPanelEl =
                element.shadowRoot.querySelector('c-error-panel');
            expect(errorPanelEl).not.toBeNull();
        });
    });
    describe('lightning-input interactions', () => {
        it('calls processImage when a picture is uploaded', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            element.recordId = 'a003h000002TzXbAAK';
            document.body.appendChild(element);

            // Emit mock property
            getRecord.emit(mockGetPropertyRecord);

            // Emit mock createFile
            createFile.mockResolvedValue('A00012345678');

            // Wait for any asynchronous DOM updates
            await flushPromises();

            // Simulate input click
            const lightningInputEl =
                element.shadowRoot.querySelector('lightning-input');
            lightningInputEl.files = [
                new File(['1234'], 'test.jpg', { type: 'image/jpeg' })
            ];
            lightningInputEl.dispatchEvent(new CustomEvent('change'));

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise((resolve) => setTimeout(resolve, 100));

            // Assertions
            expect(processImage).toHaveBeenCalled();
            expect(processImage.mock.calls[0][1]).toMatchObject({
                targetWidth: 500,
                targetHeight: 500
            });
            expect(createFile).toHaveBeenCalledWith({
                base64data: expect.any(String),
                filename: 'test.jpg',
                recordId: 'a003h000002TzXbAAK'
            });
            expect(refreshApex).toHaveBeenCalled();
        });

        it('uploads each selected picture', async () => {
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            element.recordId = 'a003h000002TzXbAAK';
            document.body.appendChild(element);

            getRecord.emit(mockGetPropertyRecord);
            createFile.mockResolvedValue('A00012345678');

            await flushPromises();

            const lightningInputEl =
                element.shadowRoot.querySelector('lightning-input');
            lightningInputEl.files = [
                new File(['1234'], 'one.jpg', { type: 'image/jpeg' }),
                new File(['5678'], 'two.png', { type: 'image/png' })
            ];
            lightningInputEl.dispatchEvent(new CustomEvent('change'));

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise((resolve) => setTimeout(resolve, 100));

            expect(processImage).toHaveBeenCalledTimes(2);
            expect(createFile).toHaveBeenCalledTimes(2);
            expect(createFile.mock.calls[1][0].filename).toBe('two.png');
            expect(refreshApex).toHaveBeenCalledTimes(2);
        });

        it('logs an error and does not refresh when the upload fails', async () => {
            const consoleErrorSpy = jest
                .spyOn(console, 'error')
                .mockImplementation(() => {});
            const element = createElement('c-property-carousel', {
                is: PropertyCarousel
            });
            document.body.appendChild(element);

            getRecord.emit(mockGetPropertyRecord);
            const uploadError = new Error('Upload failed');
            createFile.mockRejectedValue(uploadError);

            await flushPromises();

            const lightningInputEl =
                element.shadowRoot.querySelector('lightning-input');
            lightningInputEl.files = [
                new File(['1234'], 'test.jpg', { type: 'image/jpeg' })
            ];
            lightningInputEl.dispatchEvent(new CustomEvent('change'));

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise((resolve) => setTimeout(resolve, 100));

            expect(consoleErrorSpy).toHaveBeenCalledWith(
                'Error compressing and creating file: ',
                uploadError
            );
            expect(refreshApex).not.toHaveBeenCalled();
            consoleErrorSpy.mockRestore();
        });
    });
});
