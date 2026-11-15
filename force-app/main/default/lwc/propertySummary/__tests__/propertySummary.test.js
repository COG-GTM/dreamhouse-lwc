import { createElement } from '@lwc/engine-dom';
import PropertySummary from 'c/propertySummary';
import { getRecord } from 'lightning/uiRecordApi';
import { getNavigateCalledWith } from 'lightning/navigation';
import {
    publish,
    subscribe,
    unsubscribe,
    MessageContext
} from 'lightning/messageService';
import PROPERTYSELECTEDMC from '@salesforce/messageChannel/PropertySelected__c';

// Realistic property record
const mockPropertyRecord = require('./data/getRecord.json');

describe('c-property-summary', () => {
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

    it('renders an error panel when no property is selected', async () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });

        document.body.appendChild(element);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        const panelEl = element.shadowRoot.querySelector('c-error-panel');
        expect(panelEl).not.toBeNull();
        expect(panelEl.friendlyMessage).toBe(
            'Select a property to see details'
        );
    });

    it('renders an error panel when getRecord returns an error', async () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });

        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        // Simulate error
        getRecord.error();

        // Wait for any asynchronous DOM updates
        await flushPromises();

        const panelEls = element.shadowRoot.querySelectorAll('c-error-panel');
        expect(panelEls.length).toBe(1);
        expect(panelEls[0].friendlyMessage).toBe('Error retrieving data');
        expect(
            element.shadowRoot.querySelector('lightning-record-form')
        ).toBeNull();
    });

    it('renders a lightning-record-form when a property is selected', async () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        // Simulate property selection
        getRecord.emit(mockPropertyRecord);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        const formEl = element.shadowRoot.querySelector(
            'lightning-record-form'
        );
        expect(formEl).not.toBeNull();
        expect(formEl.recordId).toStrictEqual(mockPropertyRecord.id);
    });

    it('is accessible when property is selected', async () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });

        document.body.appendChild(element);

        // Simulate property selection
        getRecord.emit(mockPropertyRecord);

        // Wait for any asynchronous DOM updates
        await flushPromises();

        await expect(element).toBeAccessible();
    });

    it('is accessible when property is not selected', async () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });

        document.body.appendChild(element);

        await expect(element).toBeAccessible();
    });

    it('renders the property name, picture and form fields', async () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        getRecord.emit(mockPropertyRecord);

        await flushPromises();

        const titleEl = element.shadowRoot.querySelector('span[slot="title"]');
        expect(titleEl.textContent).toBe(mockPropertyRecord.fields.Name.value);
        const imgEl = element.shadowRoot.querySelector('img');
        expect(imgEl.src).toBe(mockPropertyRecord.fields.Picture__c.value);
        const formEl = element.shadowRoot.querySelector(
            'lightning-record-form'
        );
        expect(formEl.objectApiName).toBe('Property__c');
        expect(formEl.fields.map((field) => field.fieldApiName)).toEqual([
            'Beds__c',
            'Baths__c',
            'Price__c',
            'Broker__c'
        ]);
        expect(element.shadowRoot.querySelector('c-error-panel')).toBeNull();
    });

    it('navigates to the property record page when the expand button is clicked', async () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });
        element.recordId = mockPropertyRecord.id;
        document.body.appendChild(element);

        getRecord.emit(mockPropertyRecord);

        await flushPromises();

        const buttonEl = element.shadowRoot.querySelector(
            'lightning-button-icon'
        );
        buttonEl.click();

        const { pageReference } = getNavigateCalledWith();
        expect(pageReference).toEqual({
            type: 'standard__recordPage',
            attributes: {
                recordId: mockPropertyRecord.id,
                objectApiName: 'Property__c',
                actionName: 'view'
            }
        });
    });

    it('registers the PropertySelected subscriber during the component lifecycle', () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });
        document.body.appendChild(element);

        expect(subscribe).toHaveBeenCalled();
        expect(subscribe.mock.calls[0][1]).toBe(PROPERTYSELECTEDMC);
    });

    it('unregisters the PropertySelected subscriber when removed from the DOM', () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });
        document.body.appendChild(element);
        document.body.removeChild(element);

        expect(unsubscribe).toHaveBeenCalled();
    });

    it('invokes getRecord with the published propertyId', async () => {
        const element = createElement('c-property-summary', {
            is: PropertySummary
        });
        document.body.appendChild(element);

        publish(MessageContext, PROPERTYSELECTEDMC, {
            propertyId: mockPropertyRecord.id
        });

        await flushPromises();

        expect(element.recordId).toBe(mockPropertyRecord.id);
        expect(getRecord.getLastConfig().recordId).toBe(mockPropertyRecord.id);
        // The "no property selected" panel is gone once a property is selected
        expect(element.shadowRoot.querySelector('c-error-panel')).toBeNull();
    });
});
