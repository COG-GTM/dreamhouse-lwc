import { createElement } from '@lwc/engine-dom';
import PropertyOffers, { percentBelowTenths } from 'c/propertyOffers';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import getOfferContext from '@salesforce/apex/OfferController.getOfferContext';
import submitOffer from '@salesforce/apex/OfferController.submitOffer';
import approveOffer from '@salesforce/apex/OfferController.approveOffer';
import acceptOffer from '@salesforce/apex/OfferController.acceptOffer';
import rejectOffer from '@salesforce/apex/OfferController.rejectOffer';

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

const PROPERTY_ID = 'a0Vaj00000ec4VAEAY';
const OTHER_PROPERTY_ID = 'a0Vaj00000ec4VBEAY';

function context(overrides = {}) {
    return {
        askingPrice: 845000,
        propertyStatus: 'Available',
        canApprove: true,
        approvalThreshold: 10,
        offers: [],
        ...overrides
    };
}

const JANE = {
    id: 'a01000000000001AAA',
    buyerName: 'Jane Buyer',
    amount: 820000,
    percentBelowAsking: 3.0,
    status: 'Submitted',
    requiresApproval: false
};
const SAM = {
    id: 'a01000000000002AAA',
    buyerName: 'Sam Lowball',
    amount: 720000,
    percentBelowAsking: 14.8,
    status: 'Needs Approval',
    requiresApproval: true
};

function propertyRecord(price, status) {
    return {
        apiName: 'Property__c',
        id: PROPERTY_ID,
        fields: {
            Price__c: { value: price },
            Status__c: { value: status }
        }
    };
}

async function flushPromises() {
    for (let i = 0; i < 5; i++) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

async function createComponent(recordId = PROPERTY_ID) {
    const element = createElement('c-property-offers', {
        is: PropertyOffers
    });
    element.recordId = recordId;
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

function input(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-input')].find(
        (el) => el.label === label
    );
}

function button(element, title) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find(
        (el) => el.title === title || el.label === title
    );
}

async function type(element, label, value) {
    const field = input(element, label);
    field.value = value;
    field.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

describe('percentBelowTenths', () => {
    it('matches Apex HALF_UP rounding to one decimal', () => {
        expect(percentBelowTenths(845000, 720000)).toBe(148);
        expect(percentBelowTenths(845000, 820000)).toBe(30);
        expect(percentBelowTenths(1000, 899.5)).toBe(101);
        expect(percentBelowTenths(1000, 899.6)).toBe(100);
        expect(percentBelowTenths(1000, 1050)).toBe(-50);
        expect(percentBelowTenths(3, 2.7)).toBe(100);
    });

    it('returns null without an asking price', () => {
        expect(percentBelowTenths(null, 100)).toBeNull();
        expect(percentBelowTenths(0, 100)).toBeNull();
        expect(percentBelowTenths(1000, 'abc')).toBeNull();
    });
});

describe('c-property-offers', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders an empty offers card', async () => {
        getOfferContext.mockResolvedValue(context());
        const element = await createComponent();

        expect(getOfferContext).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID
        });
        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card.title).toBe('Offers (0)');
        expect(element.shadowRoot.textContent).toContain('No offers yet.');
        expect(button(element, 'Submit offer').disabled).toBe(true);
        await expect(element).toBeAccessible();
    });

    it('previews the discount and warns when approval is needed', async () => {
        getOfferContext.mockResolvedValue(context());
        const element = await createComponent();

        await type(element, 'Offer amount', '820000');
        let preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent.trim()).toBe('3.0% below asking');

        await type(element, 'Offer amount', '720000');
        preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent.trim()).toBe(
            '14.8% below asking, needs broker approval'
        );
        expect(preview.className).toContain('slds-text-color_error');

        await type(element, 'Offer amount', '900000');
        preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent.trim()).toBe('6.5% above asking');

        await type(element, 'Offer amount', '');
        expect(
            element.shadowRoot.querySelector('[data-id="preview"]')
        ).toBeNull();
    });

    it('uses rounded percent at the 10% boundary like Apex', async () => {
        getOfferContext.mockResolvedValue(context({ askingPrice: 1000 }));
        const element = await createComponent();

        await type(element, 'Offer amount', '899.6');
        let preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent.trim()).toBe('10.0% below asking');

        await type(element, 'Offer amount', '899.5');
        preview = element.shadowRoot.querySelector('[data-id="preview"]');
        expect(preview.textContent.trim()).toBe(
            '10.1% below asking, needs broker approval'
        );
    });

    it('submits an offer, clears the form and shows a toast', async () => {
        getOfferContext.mockResolvedValue(context());
        submitOffer.mockResolvedValue(context({ offers: [JANE] }));
        const element = await createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);

        await type(element, 'Buyer name', '  Jane Buyer ');
        await type(element, 'Offer amount', '820000');
        const submit = button(element, 'Submit offer');
        expect(submit.disabled).toBe(false);
        submit.click();
        await flushPromises();

        expect(submitOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            buyerName: 'Jane Buyer',
            amount: 820000
        });
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (1)'
        );
        expect(input(element, 'Buyer name').value).toBe('');
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('success');
        const badge = element.shadowRoot.querySelector('.slds-badge');
        expect(badge.textContent).toBe('Submitted');
    });

    it('shows Apex errors in an error toast and keeps the form', async () => {
        getOfferContext.mockResolvedValue(context());
        submitOffer.mockRejectedValue({
            body: { message: 'Offers are closed: the property is Closed.' }
        });
        const element = await createComponent();
        const toastHandler = jest.fn();
        element.addEventListener(ShowToastEventName, toastHandler);

        await type(element, 'Buyer name', 'Jane');
        await type(element, 'Offer amount', '800000');
        button(element, 'Submit offer').click();
        await flushPromises();

        const toast = toastHandler.mock.calls[0][0].detail;
        expect(toast.variant).toBe('error');
        expect(toast.message).toBe(
            'Offers are closed: the property is Closed.'
        );
        expect(input(element, 'Buyer name').value).toBe('Jane');
    });

    it('hides Accept until a broker approves', async () => {
        getOfferContext.mockResolvedValue(context({ offers: [SAM, JANE] }));
        approveOffer.mockResolvedValue(
            context({
                offers: [
                    { ...SAM, status: 'Approved', requiresApproval: false },
                    JANE
                ]
            })
        );
        const element = await createComponent();

        expect(
            button(element, 'Accept offer from Sam Lowball')
        ).toBeUndefined();
        expect(
            button(element, 'Approve offer from Jane Buyer')
        ).toBeUndefined();
        expect(button(element, 'Accept offer from Jane Buyer')).toBeDefined();

        button(element, 'Approve offer from Sam Lowball').click();
        await flushPromises();

        expect(approveOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            offerId: SAM.id
        });
        expect(button(element, 'Accept offer from Sam Lowball')).toBeDefined();
        expect(
            button(element, 'Approve offer from Sam Lowball')
        ).toBeUndefined();
    });

    it('tells agents an offer is waiting for approval', async () => {
        getOfferContext.mockResolvedValue(
            context({ canApprove: false, offers: [SAM] })
        );
        const element = await createComponent();

        expect(
            button(element, 'Approve offer from Sam Lowball')
        ).toBeUndefined();
        expect(
            button(element, 'Accept offer from Sam Lowball')
        ).toBeUndefined();
        expect(button(element, 'Reject offer from Sam Lowball')).toBeDefined();
        expect(element.shadowRoot.textContent).toContain(
            'Waiting for broker approval'
        );
    });

    it('accepts an offer and refreshes the property record', async () => {
        getOfferContext.mockResolvedValue(
            context({
                offers: [
                    { ...SAM, status: 'Approved', requiresApproval: false },
                    JANE
                ]
            })
        );
        acceptOffer.mockResolvedValue(
            context({
                propertyStatus: 'Under Agreement',
                offers: [
                    { ...SAM, status: 'Accepted', requiresApproval: false },
                    { ...JANE, status: 'Rejected' }
                ]
            })
        );
        const element = await createComponent();

        button(element, 'Accept offer from Sam Lowball').click();
        await flushPromises();

        expect(acceptOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            offerId: SAM.id
        });
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
            { recordId: PROPERTY_ID }
        ]);
        const badges = [
            ...element.shadowRoot.querySelectorAll('.slds-badge')
        ].map((el) => el.textContent);
        expect(badges).toEqual(['Accepted', 'Rejected']);
        expect(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).toHaveLength(0);
        expect(
            element.shadowRoot.querySelector('[data-id="closed"]').textContent
        ).toContain('Under Agreement');
    });

    it('rejects an offer', async () => {
        getOfferContext.mockResolvedValue(context({ offers: [JANE] }));
        rejectOffer.mockResolvedValue(
            context({ offers: [{ ...JANE, status: 'Rejected' }] })
        );
        const element = await createComponent();

        button(element, 'Reject offer from Jane Buyer').click();
        await flushPromises();

        expect(rejectOffer).toHaveBeenCalledWith({
            propertyId: PROPERTY_ID,
            offerId: JANE.id
        });
        expect(
            element.shadowRoot.querySelector('.slds-badge').textContent
        ).toBe('Rejected');
        expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    });

    it('shows a load error', async () => {
        getOfferContext.mockRejectedValue({ body: { message: 'No access' } });
        const element = await createComponent();
        expect(element.shadowRoot.textContent).toContain('No access');
    });

    it('reloads and clears the form when recordId changes', async () => {
        getOfferContext.mockResolvedValue(context());
        const element = await createComponent();
        await type(element, 'Buyer name', 'Jane');
        await type(element, 'Offer amount', '800000');

        getOfferContext.mockResolvedValue(context({ offers: [JANE] }));
        element.recordId = OTHER_PROPERTY_ID;
        await flushPromises();

        expect(getOfferContext).toHaveBeenLastCalledWith({
            propertyId: OTHER_PROPERTY_ID
        });
        expect(input(element, 'Buyer name').value).toBe('');
        expect(input(element, 'Offer amount').value).toBeUndefined();
        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (1)'
        );
    });

    it('ignores stale responses from an earlier property', async () => {
        let resolveFirst;
        getOfferContext.mockReturnValueOnce(
            new Promise((resolve) => {
                resolveFirst = resolve;
            })
        );
        const element = await createComponent();
        getOfferContext.mockResolvedValueOnce(context({ offers: [JANE] }));
        element.recordId = OTHER_PROPERTY_ID;
        await flushPromises();
        resolveFirst(context({ offers: [SAM, JANE] }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-card').title).toBe(
            'Offers (1)'
        );
    });

    it('reloads offers when the asking price or status changes', async () => {
        getOfferContext.mockResolvedValue(context({ offers: [JANE] }));
        await createComponent();
        getRecord.emit(propertyRecord(845000, 'Available'));
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(1);

        getOfferContext.mockResolvedValue(
            context({ askingPrice: 900000, offers: [JANE] })
        );
        getRecord.emit(propertyRecord(900000, 'Available'));
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(2);
    });

    it('retries once when Apex returns values older than the record', async () => {
        getOfferContext.mockResolvedValueOnce(context());
        const element = await createComponent();
        getOfferContext.mockResolvedValue(context({ askingPrice: 845000 }));
        getRecord.emit(propertyRecord(900000, 'Available'));
        await flushPromises();
        expect(getOfferContext).toHaveBeenCalledTimes(3);
        expect(
            element.shadowRoot.querySelector('lightning-card')
        ).not.toBeNull();
    });

    it('hides the form on closed properties', async () => {
        getOfferContext.mockResolvedValue(
            context({ propertyStatus: 'Closed', offers: [JANE] })
        );
        const element = await createComponent();
        expect(input(element, 'Buyer name')).toBeUndefined();
        expect(
            element.shadowRoot.querySelector('[data-id="closed"]').textContent
        ).toContain('Closed');
        expect(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).toHaveLength(0);
    });
});
