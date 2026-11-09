import { createElement } from '@lwc/engine-dom';
import PropertyOffers, { percentBelowAsking } from 'c/propertyOffers';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getOffers from '@salesforce/apex/OfferController.getOffers';
import canApprove from '@salesforce/apex/OfferController.canApprove';
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
    '@salesforce/apex/OfferController.canApprove',
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

function propertyRecord(status = 'Available') {
    return {
        apiName: 'Property__c',
        id: PROPERTY_ID,
        fields: {
            Price__c: { value: 845000, displayValue: '$845,000' },
            Status__c: { value: status, displayValue: status }
        }
    };
}

const JANE = {
    Id: 'a1Offer0000000001',
    Buyer_Name__c: 'Jane Buyer',
    Amount__c: 820000,
    Percent_Below_Asking__c: 3.0,
    Status__c: 'Submitted'
};
const SAM = {
    Id: 'a1Offer0000000002',
    Buyer_Name__c: 'Sam Lowball',
    Amount__c: 720000,
    Percent_Below_Asking__c: 14.8,
    Status__c: 'Needs Approval'
};

function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render({ status, offers = [], broker = false } = {}) {
    const element = createElement('c-property-offers', { is: PropertyOffers });
    element.recordId = PROPERTY_ID;
    document.body.appendChild(element);
    getRecord.emit(propertyRecord(status));
    getOffers.emit(offers);
    canApprove.emit(broker);
    await flushPromises();
    return element;
}

function input(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-input')].find(
        (el) => el.label === label
    );
}

function button(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find(
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

describe('percentBelowAsking', () => {
    it('rounds to one decimal place like OfferService', () => {
        expect(percentBelowAsking(845000, 720000)).toBe(14.8);
        expect(percentBelowAsking(845000, 820000)).toBe(3.0);
        expect(percentBelowAsking(845000, 760500)).toBe(10.0);
        expect(percentBelowAsking(845000, 887250)).toBe(-5.0);
        expect(percentBelowAsking(0, 100)).toBeNull();
        expect(percentBelowAsking(845000, 0)).toBeNull();
    });
});

describe('c-property-offers', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows an empty Offers (0) card with the offer form', async () => {
        const element = await render();
        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card.title).toBe('Offers (0)');
        expect(element.shadowRoot.querySelector('.no-offers')).not.toBeNull();
        expect(button(element, 'Submit offer').disabled).toBe(true);
    });

    it('previews % below asking and warns past the approval threshold', async () => {
        const element = await render();
        await type(element, 'Buyer name', 'Sam Lowball');
        await type(element, 'Offer amount', '720000');
        const preview = element.shadowRoot.querySelector('.preview');
        expect(preview.textContent).toContain(
            '14.8% below asking, needs broker approval'
        );
        expect(preview.classList).toContain('slds-text-color_error');
        expect(button(element, 'Submit offer').disabled).toBe(false);

        await type(element, 'Offer amount', '760500');
        expect(
            element.shadowRoot.querySelector('.preview').textContent
        ).toContain('10.0% below asking');
        expect(
            element.shadowRoot.querySelector('.preview').textContent
        ).not.toContain('approval');

        await type(element, 'Offer amount', '887250');
        expect(
            element.shadowRoot.querySelector('.preview').textContent
        ).toContain('5.0% above asking');
    });

    it('submits an offer, toasts, clears the form and refreshes the list', async () => {
        submitOffer.mockResolvedValue(SAM);
        const element = await render();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);

        await type(element, 'Buyer name', ' Sam Lowball ');
        await type(element, 'Offer amount', '720000');
        button(element, 'Submit offer').click();
        await flushPromises();

        expect(submitOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            buyerName: 'Sam Lowball',
            amount: 720000
        });
        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Offer from Sam Lowball submitted. It needs broker approval.'
        );
        expect(refreshApex).toHaveBeenCalled();
        expect(input(element, 'Buyer name').value).toBe('');
    });

    it('shows an error toast when the submit fails', async () => {
        submitOffer.mockRejectedValue({
            body: {
                message: 'This property is Closed and is not taking offers.'
            }
        });
        const element = await render();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);

        await type(element, 'Buyer name', 'Jane Buyer');
        await type(element, 'Offer amount', '820000');
        button(element, 'Submit offer').click();
        await flushPromises();

        const toast = toastHandler.mock.calls[0][0].detail;
        expect(toast.variant).toBe('error');
        expect(toast.message).toBe(
            'This property is Closed and is not taking offers.'
        );
        expect(input(element, 'Buyer name').value).toBe('Jane Buyer');
    });

    it('lists offers with status badges and hides Accept until approved', async () => {
        const element = await render({ offers: [SAM, JANE] });
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (2)'
        );
        const badges = [
            ...element.shadowRoot.querySelectorAll('[data-status]')
        ].map((el) => el.textContent);
        expect(badges).toEqual(['Needs Approval', 'Submitted']);

        const accepts = buttons(element, 'Accept');
        expect(accepts).toHaveLength(1);
        expect(accepts[0].dataset.id).toBe(JANE.Id);
        expect(buttons(element, 'Approve')).toHaveLength(0);
        expect(element.shadowRoot.textContent).toContain(
            'Waiting for broker approval'
        );
    });

    it('lets a broker approve an offer that needs approval', async () => {
        approveOffer.mockResolvedValue();
        const element = await render({ offers: [SAM], broker: true });
        const approve = button(element, 'Approve');
        expect(approve.dataset.id).toBe(SAM.Id);
        approve.click();
        await flushPromises();
        expect(approveOffer).toHaveBeenCalledWith({ offerId: SAM.Id });
        expect(refreshApex).toHaveBeenCalled();
    });

    it('accepts an offer and refreshes the property record', async () => {
        acceptOffer.mockResolvedValue();
        const element = await render({
            offers: [{ ...SAM, Status__c: 'Approved' }, JANE],
            broker: true
        });
        buttons(element, 'Accept')[0].click();
        await flushPromises();
        expect(acceptOffer).toHaveBeenCalledWith({ offerId: SAM.Id });
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
            { recordId: PROPERTY_ID }
        ]);
    });

    it('rejects an offer', async () => {
        rejectOffer.mockResolvedValue();
        const element = await render({ offers: [JANE] });
        button(element, 'Reject').click();
        await flushPromises();
        expect(rejectOffer).toHaveBeenCalledWith({ offerId: JANE.Id });
    });

    it('closes the form and actions once the property is Under Agreement', async () => {
        const element = await render({
            status: 'Under Agreement',
            offers: [
                { ...SAM, Status__c: 'Accepted' },
                { ...JANE, Status__c: 'Rejected' }
            ],
            broker: true
        });
        expect(
            element.shadowRoot.querySelector('.closed-message').textContent
        ).toContain('Under Agreement');
        expect(element.shadowRoot.querySelector('.offer-form')).toBeNull();
        expect(buttons(element, 'Accept')).toHaveLength(0);
        expect(buttons(element, 'Reject')).toHaveLength(0);
        expect(buttons(element, 'Approve')).toHaveLength(0);
    });

    it('shows an error panel when offers fail to load', async () => {
        const element = createElement('c-property-offers', {
            is: PropertyOffers
        });
        element.recordId = PROPERTY_ID;
        document.body.appendChild(element);
        getRecord.emit(propertyRecord());
        getOffers.error();
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('c-error-panel')
        ).not.toBeNull();
    });

    it('is accessible', async () => {
        const element = await render({ offers: [SAM, JANE], broker: true });
        await expect(element).toBeAccessible();
    });
});
