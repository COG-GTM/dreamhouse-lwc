import { createElement } from '@lwc/engine-dom';
import PropertyOffers, { percentBelowAsking } from 'c/propertyOffers';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getOfferContext from '@salesforce/apex/OfferController.getOfferContext';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';

const SHOW_TOAST_EVENT = 'lightning__showtoast';

jest.mock(
    '@salesforce/apex/OfferController.getOfferContext',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.submitOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.approveOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.acceptOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OfferController.rejectOffer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('lightning/uiRecordApi', () => {
    const {
        createLdsTestWireAdapter
    } = require('@salesforce/wire-service-jest-util');
    return {
        getRecord: createLdsTestWireAdapter(jest.fn()),
        getFieldValue: jest.requireActual('lightning/uiRecordApi')
            .getFieldValue,
        notifyRecordUpdateAvailable: jest.fn(() => Promise.resolve())
    };
});

const PROPERTY_ID = 'a0Vaj00000ec4VAEAY';

function propertyRecord(status = 'Available', price = 845000) {
    return {
        apiName: 'Property__c',
        id: PROPERTY_ID,
        fields: {
            Price__c: { value: price, displayValue: null },
            Status__c: { value: status, displayValue: null }
        }
    };
}

function offer(id, buyer, amount, percent, status) {
    return {
        Id: id,
        Buyer_Name__c: buyer,
        Amount__c: amount,
        Percent_Below_Asking__c: percent,
        Status__c: status
    };
}

const JANE = offer('a0W1', 'Jane Buyer', 820000, 3.0, 'Submitted');
const SAM = offer('a0W2', 'Sam Lowball', 720000, 14.8, 'Needs Approval');

function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render({ offers = [], canApprove = true, status } = {}) {
    getOfferContext.mockResolvedValue({ offers, canApprove });
    const element = createElement('c-property-offers', { is: PropertyOffers });
    element.recordId = PROPERTY_ID;
    document.body.appendChild(element);
    getRecord.emit(propertyRecord(status));
    await flushPromises();
    return element;
}

function input(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-input')].find(
        (el) => el.label === label
    );
}

function buttons(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].filter(
        (el) => el.label === label
    );
}

async function type(element, label, value) {
    const field = input(element, label);
    field.value = value;
    field.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

function previewText(element) {
    const preview = element.shadowRoot.querySelector('[data-id="preview"]');
    return preview ? preview.textContent.trim() : null;
}

describe('percentBelowAsking', () => {
    it('rounds half-up to one decimal place like Apex', () => {
        expect(percentBelowAsking(845000, 720000)).toBe(14.8);
        expect(percentBelowAsking(845000, 820000)).toBe(3);
        expect(percentBelowAsking(1000000, 899500)).toBe(10.1);
        expect(percentBelowAsking(1000000, 899600)).toBe(10);
        expect(percentBelowAsking(1000000, 1050000)).toBe(-5);
        expect(percentBelowAsking(100, 100)).toBe(0);
    });

    it('stays exact just below the rounding boundary', () => {
        expect(percentBelowAsking(99999999, 89949999.11)).toBe(10);
        expect(percentBelowAsking(99999999, 89949999.1)).toBe(10.1);
    });

    it('returns null without a price or amount', () => {
        expect(percentBelowAsking(null, 100)).toBeNull();
        expect(percentBelowAsking(0, 100)).toBeNull();
        expect(percentBelowAsking(100, null)).toBeNull();
        expect(percentBelowAsking(100, '')).toBeNull();
        expect(percentBelowAsking(100, 'abc')).toBeNull();
    });
});

describe('c-property-offers', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows an empty Offers (0) card', async () => {
        const element = await render();
        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card.title).toBe('Offers (0)');
        expect(element.shadowRoot.querySelector('.empty')).not.toBeNull();
        expect(getOfferContext).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID
        });
        expect(buttons(element, 'Submit offer')[0].disabled).toBe(true);
    });

    it('previews the discount and warns when approval is needed', async () => {
        const element = await render();
        await type(element, 'Offer amount', 820000);
        expect(previewText(element)).toBe('3.0% below asking');

        await type(element, 'Offer amount', 720000);
        expect(previewText(element)).toBe(
            '14.8% below asking, needs broker approval'
        );
        expect(
            element.shadowRoot.querySelector('lightning-icon')
        ).not.toBeNull();

        await type(element, 'Offer amount', 900000);
        expect(previewText(element)).toBe('6.5% above asking');

        await type(element, 'Offer amount', '');
        expect(previewText(element)).toBeNull();
    });

    it('submits an offer and reloads the list', async () => {
        submitOffer.mockResolvedValue(SAM);
        const element = await render();
        const handler = jest.fn();
        element.addEventListener(SHOW_TOAST_EVENT, handler);

        await type(element, 'Buyer name', 'Sam Lowball');
        await type(element, 'Offer amount', 720000);
        getOfferContext.mockResolvedValue({ offers: [SAM], canApprove: true });
        buttons(element, 'Submit offer')[0].click();
        await flushPromises();

        expect(submitOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            buyerName: 'Sam Lowball',
            amount: 720000
        });
        expect(handler.mock.calls[0][0].detail.variant).toBe('success');
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (1)'
        );
        expect(input(element, 'Buyer name').value).toBe('');
    });

    it('shows an error toast when submit fails', async () => {
        submitOffer.mockRejectedValue({
            body: { message: 'Offer amount must be greater than zero.' }
        });
        const element = await render();
        const handler = jest.fn();
        element.addEventListener(SHOW_TOAST_EVENT, handler);

        await type(element, 'Buyer name', 'Jane Buyer');
        await type(element, 'Offer amount', 5);
        buttons(element, 'Submit offer')[0].click();
        await flushPromises();

        const toast = handler.mock.calls[0][0].detail;
        expect(toast.variant).toBe('error');
        expect(toast.message).toBe('Offer amount must be greater than zero.');
        expect(input(element, 'Buyer name').value).toBe('Jane Buyer');
    });

    it('renders status badges and the right buttons for a broker', async () => {
        const element = await render({ offers: [SAM, JANE] });
        const badges = [
            ...element.shadowRoot.querySelectorAll('[data-status]')
        ].map((badge) => badge.textContent.trim());
        expect(badges).toEqual(['Needs Approval', 'Submitted']);

        const approve = buttons(element, 'Approve');
        const accept = buttons(element, 'Accept');
        expect(approve).toHaveLength(1);
        expect(approve[0].dataset.id).toBe(SAM.Id);
        expect(accept).toHaveLength(1);
        expect(accept[0].dataset.id).toBe(JANE.Id);
        expect(buttons(element, 'Reject')).toHaveLength(2);
    });

    it('hides Approve from agents without the permission', async () => {
        const element = await render({ offers: [SAM], canApprove: false });
        expect(buttons(element, 'Approve')).toHaveLength(0);
        expect(buttons(element, 'Accept')).toHaveLength(0);
        expect(buttons(element, 'Reject')).toHaveLength(1);
    });

    it('approves an offer', async () => {
        approveOffer.mockResolvedValue();
        const element = await render({ offers: [SAM] });
        getOfferContext.mockResolvedValue({
            offers: [{ ...SAM, Status__c: 'Approved' }],
            canApprove: true
        });
        buttons(element, 'Approve')[0].click();
        await flushPromises();

        expect(approveOffer).toHaveBeenCalledWith({ offerId: SAM.Id });
        expect(buttons(element, 'Approve')).toHaveLength(0);
        expect(buttons(element, 'Accept')).toHaveLength(1);
    });

    it('accepts an offer and refreshes the property record', async () => {
        acceptOffer.mockResolvedValue();
        const element = await render({ offers: [JANE] });
        getOfferContext.mockResolvedValue({
            offers: [{ ...JANE, Status__c: 'Accepted' }],
            canApprove: true
        });
        buttons(element, 'Accept')[0].click();
        await flushPromises();

        expect(acceptOffer).toHaveBeenCalledWith({ offerId: JANE.Id });
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
            { recordId: PROPERTY_ID }
        ]);
    });

    it('does not refresh the record when accept fails', async () => {
        acceptOffer.mockRejectedValue({ body: { message: 'Nope' } });
        const element = await render({ offers: [JANE] });
        buttons(element, 'Accept')[0].click();
        await flushPromises();
        expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    });

    it('rejects an offer', async () => {
        rejectOffer.mockResolvedValue();
        const element = await render({ offers: [JANE] });
        buttons(element, 'Reject')[0].click();
        await flushPromises();
        expect(rejectOffer).toHaveBeenCalledWith({ offerId: JANE.Id });
    });

    it('stops taking offers once the property is Under Agreement', async () => {
        const element = await render({
            offers: [
                { ...SAM, Status__c: 'Accepted' },
                { ...JANE, Status__c: 'Rejected' }
            ],
            status: 'Under Agreement'
        });
        expect(
            element.shadowRoot.querySelector('.closed-notice')
        ).not.toBeNull();
        expect(input(element, 'Buyer name')).toBeUndefined();
        expect(buttons(element, 'Accept')).toHaveLength(0);
        expect(buttons(element, 'Reject')).toHaveLength(0);
    });

    it('shows an error panel when offers fail to load', async () => {
        getOfferContext.mockRejectedValue({ body: { message: 'boom' } });
        const element = createElement('c-property-offers', {
            is: PropertyOffers
        });
        element.recordId = PROPERTY_ID;
        document.body.appendChild(element);
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('c-error-panel')
        ).not.toBeNull();
        expect(element.shadowRoot.querySelector('.empty')).toBeNull();
    });

    it('reloads offers when the record changes', async () => {
        const element = await render({ offers: [JANE] });
        expect(buttons(element, 'Accept')).toHaveLength(1);

        getOfferContext.mockResolvedValue({ offers: [], canApprove: true });
        element.recordId = 'a0Vother';
        await flushPromises();

        expect(getOfferContext).toHaveBeenLastCalledWith({
            propertyId: 'a0Vother'
        });
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (0)'
        );
        expect(buttons(element, 'Accept')).toHaveLength(0);
    });

    it('ignores a slow response from an earlier request', async () => {
        let resolveFirst;
        getOfferContext.mockReturnValueOnce(
            new Promise((resolve) => {
                resolveFirst = resolve;
            })
        );
        getOfferContext.mockResolvedValueOnce({
            offers: [JANE],
            canApprove: true
        });
        const element = createElement('c-property-offers', {
            is: PropertyOffers
        });
        element.recordId = PROPERTY_ID;
        document.body.appendChild(element);
        getRecord.emit(propertyRecord());
        element.recordId = 'a0Vother';
        await flushPromises();

        resolveFirst({ offers: [SAM, JANE], canApprove: true });
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (1)'
        );
    });

    it('is accessible', async () => {
        const element = await render({ offers: [SAM, JANE] });
        await expect(element).toBeAccessible();
    });
});
