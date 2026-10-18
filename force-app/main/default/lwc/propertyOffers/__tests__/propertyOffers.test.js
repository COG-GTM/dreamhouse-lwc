import { createElement } from '@lwc/engine-dom';
import PropertyOffers, { percentBelowAsking } from 'c/propertyOffers';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import getOffers from '@salesforce/apex/OfferController.getOffers';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';

jest.mock(
    '@salesforce/apex/OfferController.getOffers',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
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
        Name: `OFR-${id}`,
        Buyer_Name__c: buyer,
        Amount__c: amount,
        Percent_Below_Asking__c: percent,
        Status__c: status
    };
}

const JANE = offer('a1', 'Jane Buyer', 820000, 3.0, 'Submitted');
const SAM = offer('a2', 'Sam Lowball', 720000, 14.8, 'Needs Approval');

describe('c-property-offers', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    async function flushPromises() {
        for (let i = 0; i < 5; i++) {
            // eslint-disable-next-line no-await-in-loop
            await Promise.resolve();
        }
    }

    function createComponent({
        status = 'Available',
        offers = [],
        canApprove = false
    } = {}) {
        const element = createElement('c-property-offers', {
            is: PropertyOffers
        });
        element.recordId = PROPERTY_ID;
        document.body.appendChild(element);
        getRecord.emit(propertyRecord(status));
        getOffers.emit({ offers, canApprove });
        return element;
    }

    function buttons(element, label) {
        return Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).filter((button) => button.label === label);
    }

    function setInput(element, label, value) {
        const input = Array.from(
            element.shadowRoot.querySelectorAll('lightning-input')
        ).find((i) => i.label === label);
        input.value = value;
        input.dispatchEvent(new CustomEvent('change'));
    }

    describe('percentBelowAsking', () => {
        it('rounds half up to one decimal like Apex', () => {
            expect(percentBelowAsking(845000, 720000)).toBe(14.8);
            expect(percentBelowAsking(845000, 820000)).toBe(3);
            expect(percentBelowAsking(845000, 760500)).toBe(10);
            expect(percentBelowAsking(100000, 89950)).toBe(10.1);
            expect(percentBelowAsking(100000, 105000)).toBe(-5);
        });

        it('returns null without an asking price or amount', () => {
            expect(percentBelowAsking(null, 1)).toBeNull();
            expect(percentBelowAsking(0, 1)).toBeNull();
            expect(percentBelowAsking(845000, undefined)).toBeNull();
        });
    });

    it('shows an empty card with the offer count', async () => {
        const element = createComponent();
        await flushPromises();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card.title).toBe('Offers (0)');
        expect(element.shadowRoot.querySelector('.empty')).not.toBeNull();
        expect(buttons(element, 'Submit offer')[0].disabled).toBe(true);
    });

    it('previews % below asking and warns when approval is needed', async () => {
        const element = createComponent();
        await flushPromises();

        setInput(element, 'Buyer name', 'Sam Lowball');
        setInput(element, 'Offer amount', '720000');
        await flushPromises();

        const preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent).toBe(
            '14.8% below asking, needs broker approval'
        );
        expect(preview.className).toContain('slds-text-color_error');
        expect(buttons(element, 'Submit offer')[0].disabled).toBe(false);

        setInput(element, 'Offer amount', '820000');
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('[data-id="preview"]').textContent
        ).toBe('3.0% below asking');

        setInput(element, 'Offer amount', '900000');
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('[data-id="preview"]').textContent
        ).toBe('6.5% above asking');
    });

    it('submits an offer, refreshes and toasts', async () => {
        submitOffer.mockResolvedValue({ ...SAM });
        const element = createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        await flushPromises();

        setInput(element, 'Buyer name', 'Sam Lowball');
        setInput(element, 'Offer amount', '720000');
        await flushPromises();
        buttons(element, 'Submit offer')[0].click();
        await flushPromises();

        expect(submitOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            buyerName: 'Sam Lowball',
            amount: 720000
        });
        expect(refreshApex).toHaveBeenCalled();
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
            { recordId: PROPERTY_ID }
        ]);
        expect(toastHandler.mock.calls[0][0].detail).toEqual({
            title: 'Offer submitted: needs broker approval',
            variant: 'success'
        });
    });

    it('shows an error toast when submit fails', async () => {
        submitOffer.mockRejectedValue({
            body: { message: 'Offer amount must be greater than zero.' }
        });
        const element = createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        await flushPromises();

        setInput(element, 'Buyer name', 'Zero');
        setInput(element, 'Offer amount', '5');
        await flushPromises();
        buttons(element, 'Submit offer')[0].click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail).toEqual({
            title: 'Offer amount must be greater than zero.',
            variant: 'error'
        });
    });

    it('lists offers with badges and only valid actions for an agent', async () => {
        const element = createComponent({ offers: [SAM, JANE] });
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (2)'
        );
        const badges = element.shadowRoot.querySelectorAll('[data-status]');
        expect(badges[0].textContent).toBe('Needs Approval');
        expect(badges[0].className).toContain('slds-theme_warning');
        expect(badges[1].textContent).toBe('Submitted');

        expect(buttons(element, 'Approve')).toHaveLength(0);
        const accept = buttons(element, 'Accept');
        expect(accept).toHaveLength(1);
        expect(accept[0].dataset.id).toBe(JANE.Id);
        expect(buttons(element, 'Reject')).toHaveLength(2);
    });

    it('lets a broker approve a Needs Approval offer', async () => {
        approveOffer.mockResolvedValue();
        const element = createComponent({ offers: [SAM], canApprove: true });
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        await flushPromises();

        const approve = buttons(element, 'Approve');
        expect(approve).toHaveLength(1);
        expect(buttons(element, 'Accept')).toHaveLength(0);
        approve[0].click();
        await flushPromises();

        expect(approveOffer).toHaveBeenCalledWith({ offerId: SAM.Id });
        expect(refreshApex).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Offer approved'
        );
    });

    it('accepts and rejects offers', async () => {
        acceptOffer.mockResolvedValue();
        rejectOffer.mockRejectedValue({
            body: { message: 'Only open offers can be rejected.' }
        });
        const element = createComponent({
            offers: [{ ...SAM, Status__c: 'Approved' }, JANE]
        });
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);
        await flushPromises();

        buttons(element, 'Accept')[0].click();
        await flushPromises();
        expect(acceptOffer).toHaveBeenCalledWith({ offerId: SAM.Id });
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Offer accepted'
        );

        buttons(element, 'Reject')[1].click();
        await flushPromises();
        expect(rejectOffer).toHaveBeenCalledWith({ offerId: JANE.Id });
        expect(toastHandler.mock.calls[1][0].detail).toEqual({
            title: 'Only open offers can be rejected.',
            variant: 'error'
        });
    });

    it('hides the form and accept on a property under agreement', async () => {
        const element = createComponent({
            status: 'Under Agreement',
            offers: [
                { ...SAM, Status__c: 'Accepted' },
                { ...JANE, Status__c: 'Rejected' }
            ]
        });
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('.closed-message').textContent
        ).toContain('Under Agreement');
        expect(buttons(element, 'Submit offer')).toHaveLength(0);
        expect(buttons(element, 'Accept')).toHaveLength(0);
        expect(buttons(element, 'Reject')).toHaveLength(0);
        const badges = element.shadowRoot.querySelectorAll('[data-status]');
        expect(badges[0].className).toContain('slds-theme_success');
        expect(badges[1].className).toContain('slds-theme_error');
    });

    it('shows wire errors', async () => {
        const element = createElement('c-property-offers', {
            is: PropertyOffers
        });
        element.recordId = PROPERTY_ID;
        document.body.appendChild(element);
        getOffers.error({ message: 'Insufficient access' });
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('.error').textContent
        ).toContain('Insufficient access');
    });

    it('is accessible', async () => {
        const element = createComponent({ offers: [SAM, JANE] });
        await flushPromises();
        await expect(element).toBeAccessible();
    });
});
